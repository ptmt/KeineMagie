package main

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

type appleChallenge struct {
	ID      string `json:"challenge_id"`
	Nonce   string `json:"nonce"`
	State   string `json:"state"`
	expires time.Time
}
type authRate struct {
	start time.Time
	count int
}
type appleAuth struct {
	rates      map[string]authRate
	mu         sync.Mutex
	challenges map[string]appleChallenge
	now        func() time.Time
	store      *authStore
	keys       *appleKeys
	clientID   string
}

func randomAuthToken() string {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		panic("secure random source unavailable")
	}
	return base64.RawURLEncoding.EncodeToString(b)
}
func constantAuthEqual(a, b string) bool {
	x := sha256.Sum256([]byte(a))
	y := sha256.Sum256([]byte(b))
	return subtle.ConstantTimeCompare(x[:], y[:]) == 1
}
func newAppleAuth(cfg *serverConfig) (*appleAuth, error) {
	path := cfg.authPath
	if path == "" {
		path = "data/auth.json"
	}
	store, err := openAuthStore(path)
	if err != nil {
		return nil, err
	}
	client := cfg.appleHTTPClient
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Second}
	}
	// Clone so redirects are forbidden even if the injected client's defaults allow them.
	copyClient := *client
	copyClient.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	id := cfg.appleClientID
	if id == "" {
		id = "de.keinemagie.app"
	}
	return &appleAuth{challenges: map[string]appleChallenge{}, now: time.Now, store: store, keys: &appleKeys{client: &copyClient}, clientID: id}, nil
}
func (a *appleAuth) challenge(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if r.Method != http.MethodPost {
		writeError(w, 405, "method not allowed")
		return
	}
	c := appleChallenge{ID: randomAuthToken(), Nonce: randomAuthToken(), State: randomAuthToken(), expires: a.now().Add(5 * time.Minute)}
	a.mu.Lock()
	now := a.now()
	for id, v := range a.challenges {
		if !now.Before(v.expires) {
			delete(a.challenges, id)
		}
	}
	if !a.allowLocked(r, 20) || len(a.challenges) >= 1024 {
		a.mu.Unlock()
		writeError(w, 429, "authentication unavailable")
		return
	}
	a.challenges[c.ID] = c
	a.mu.Unlock()
	writeJSON(w, 200, c)
}
func (a *appleAuth) exchange(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if r.Method != "POST" {
		writeError(w, 405, "method not allowed")
		return
	}
	var input struct {
		ChallengeID   string `json:"challenge_id"`
		IdentityToken string `json:"identity_token"`
		State         string `json:"state"`
	}
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16384))
	d.DisallowUnknownFields()
	defer r.Body.Close()
	if d.Decode(&input) != nil || d.Decode(new(any)) != io.EOF {
		writeError(w, 400, "invalid request")
		return
	}
	a.mu.Lock()
	c, ok := a.challenges[input.ChallengeID]
	delete(a.challenges, input.ChallengeID)
	if !a.allowLocked(r, 60) {
		a.mu.Unlock()
		writeError(w, 429, "authentication unavailable")
		return
	}
	a.mu.Unlock()
	if !ok || !a.now().Before(c.expires) || !constantAuthEqual(input.State, c.State) {
		writeError(w, 401, "authentication failed")
		return
	}
	sub, err := a.verify(r.Context(), input.IdentityToken, c)
	if err != nil {
		writeError(w, 401, "authentication failed")
		return
	}
	token, session, err := a.store.create(sub, a.now())
	if err != nil {
		writeError(w, 503, "authentication unavailable")
		return
	}
	writeJSON(w, 200, map[string]any{"session_token": token, "user": map[string]string{"id": session.UserID}, "expires_at": session.Expires})
}
func bearerSession(r *http.Request) string {
	parts := strings.Fields(r.Header.Get("Authorization"))
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || len(parts[1]) != 43 {
		return ""
	}
	return parts[1]
}
func (a *appleAuth) session(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if r.Method != "GET" {
		writeError(w, 405, "method not allowed")
		return
	}
	session, err := a.store.lookup(bearerSession(r), a.now())
	if err != nil {
		writeError(w, 401, "authentication failed")
		return
	}
	writeJSON(w, 200, map[string]any{"user": map[string]string{"id": session.UserID}, "expires_at": session.Expires})
}

func (a *appleAuth) logout(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if r.Method != "POST" {
		writeError(w, 405, "method not allowed")
		return
	}
	if err := a.store.revoke(bearerSession(r), a.now()); err != nil {
		writeError(w, 401, "authentication failed")
		return
	}
	w.WriteHeader(204)
}

// Caller holds a.mu. Trust only the direct peer, never user-supplied forwarding headers.
func (a *appleAuth) allowLocked(r *http.Request, limit int) bool {
	now := a.now()
	if a.rates == nil {
		a.rates = map[string]authRate{}
	}
	for key, v := range a.rates {
		if now.Sub(v.start) >= time.Minute {
			delete(a.rates, key)
		}
	}
	ip, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		ip = r.RemoteAddr
	}
	key := r.URL.Path + "|" + ip
	v, ok := a.rates[key]
	if !ok {
		if len(a.rates) >= 2048 {
			return false
		}
		v.start = now
	}
	if v.count >= limit {
		return false
	}
	v.count++
	a.rates[key] = v
	return true
}
func (cfg *serverConfig) sessionProviderPending(w http.ResponseWriter, r *http.Request) bool {
	if cfg.auth == nil {
		return false
	}
	token := bearerSession(r)
	if cfg.authToken != "" && constantAuthEqual(token, cfg.authToken) {
		return false
	}
	if token == "" {
		return false
	}
	// A session-shaped bearer must never fall through to legacy shared credentials,
	// including on a storage read error or if it has expired/revoked.
	w.Header().Set("Cache-Control", "no-store")
	if _, err := cfg.auth.store.lookup(token, cfg.auth.now()); err != nil {
		writeError(w, 401, "authentication failed")
		return true
	}
	writeError(w, 503, "provider connection pending")
	return true
}
