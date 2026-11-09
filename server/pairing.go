package main

import (
	"crypto/rand"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"time"
)

const browserCookie = "__Host-km-session"
const pairingCookie = "__Host-km-pairing"

type browserPair struct {
	Secret, Code, Approval, Owner, Native string
	Expires, Next                         time.Time
	Polls                                 int
	Approved                              bool
}
type browserAuth struct {
	apple  *appleWeb
	cfg    *serverConfig
	mu     sync.Mutex
	pairs  map[string]*browserPair
	origin string
}

func newBrowserAuth(cfg *serverConfig) *browserAuth {
	origin := strings.TrimRight(os.Getenv("WEB_ORIGIN"), "/")
	if origin == "" {
		origin = "https://keinemagie.tinyserve.org"
	}
	return &browserAuth{cfg: cfg, pairs: map[string]*browserPair{}, origin: origin}
}
func browserCSRF(secret string) string { return sessionHash("browser-csrf-v1\x00" + secret) }
func cookieValue(r *http.Request, name string) string {
	c, e := r.Cookie(name)
	if e != nil || len(c.Value) != 43 {
		return ""
	}
	return c.Value
}
func browserSetCookie(w http.ResponseWriter, name, value string, age int) {
	http.SetCookie(w, &http.Cookie{Name: name, Value: value, Path: "/", Secure: true, HttpOnly: true, SameSite: http.SameSiteStrictMode, MaxAge: age})
}
func (b *browserAuth) mutation(w http.ResponseWriter, r *http.Request, secret string) bool {
	if r.Header.Get("Origin") != b.origin || secret == "" || !constantAuthEqual(r.Header.Get("X-CSRF-Token"), browserCSRF(secret)) {
		writeError(w, 403, "browser request denied")
		return false
	}
	return true
}
func (b *browserAuth) allowed(r *http.Request, n int) bool {
	a := b.cfg.auth
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.allowLocked(r, n)
}
func (b *browserAuth) clean() {
	for k, p := range b.pairs {
		if !b.cfg.auth.now().Before(p.Expires) {
			delete(b.pairs, k)
		}
	}
}
func (b *browserAuth) handle(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	switch r.URL.Path {
	case "/v1/web/config":
		if r.Method != "GET" {
			writeError(w, 405, "method not allowed")
			return
		}
		// Cross-origin callers cannot plant or rotate the bootstrap cookie.
		if o := r.Header.Get("Origin"); o != "" && o != b.origin {
			writeError(w, 403, "browser request denied")
			return
		}
		if r.Header.Get("Sec-Fetch-Site") == "cross-site" {
			writeError(w, 403, "browser request denied")
			return
		}
		secret := cookieValue(r, pairingCookie)
		if secret == "" {
			if !b.allowed(r, 20) {
				writeError(w, 429, "try later")
				return
			}
			secret = randomAuthToken()
			browserSetCookie(w, pairingCookie, secret, 300)
		}
		reason := ""
		if b.apple == nil {
			reason = "Apple web Services ID is not configured. Use approval in the signed-in iOS app."
		}
		writeJSON(w, 200, map[string]any{"apple_available": b.apple != nil, "apple_reason": reason, "pairing_available": true, "csrf_token": browserCSRF(secret), "chatgpt_connect_available": len(b.cfg.provider.key) == 32})
	case "/v1/web/session":
		if r.Method != "GET" {
			writeError(w, 405, "method not allowed")
			return
		}
		token := cookieValue(r, browserCookie)
		s, e := b.cfg.auth.store.lookup(token, b.cfg.auth.now())
		if e != nil || s.Kind != "browser" {
			writeError(w, 401, "authentication required")
			return
		}
		clone := r.Clone(r.Context())
		clone.URL.Path = "/v1/provider"
		clone.Header.Set("Authorization", "Bearer "+token)
		status := httptest.NewRecorder()
		b.cfg.provider.handle(status, clone)
		var provider map[string]any
		if status.Code != 200 || json.Unmarshal(status.Body.Bytes(), &provider) != nil {
			provider = map[string]any{"connected": false, "reason": "provider status unavailable"}
		}
		writeJSON(w, 200, map[string]any{"user": map[string]string{"id": s.UserID}, "csrf_token": browserCSRF(token), "provider": provider, "expires_at": s.Expires})
	case "/v1/web/logout":
		if r.Method != "POST" {
			writeError(w, 405, "method not allowed")
			return
		}
		token := cookieValue(r, browserCookie)
		if !b.mutation(w, r, token) {
			return
		}
		if e := b.cfg.auth.store.revoke(token, b.cfg.auth.now()); e != nil {
			writeError(w, 401, "authentication required")
			return
		}
		browserSetCookie(w, browserCookie, "", -1)
		browserSetCookie(w, pairingCookie, "", -1)
		if b.apple != nil {
			b.apple.cancel(r)
		}
		appleTransactionSetCookie(w, "", -1)
		w.WriteHeader(204)
	case "/v1/web/pairing/start", "/v1/web/pairing/poll":
		if r.Method != "POST" {
			writeError(w, 405, "method not allowed")
			return
		}
		secret := cookieValue(r, pairingCookie)
		if !b.mutation(w, r, secret) {
			return
		}
		if !b.allowed(r, 100) {
			writeError(w, 429, "try later")
			return
		}
		var input struct{}
		if !decodeProvider(w, r, &input) {
			return
		}
		b.mu.Lock()
		defer b.mu.Unlock()
		b.clean()
		key := sessionHash(secret)
		if strings.HasSuffix(r.URL.Path, "/start") {
			if !b.allowedStart(r) || len(b.pairs) >= 1024 {
				writeError(w, 429, "try later")
				return
			}
			// 40 random bits, rendered in an unambiguous alphabet. Never reuse an active code.
			var code string
			for {
				raw := make([]byte, 8)
				if _, e := rand.Read(raw); e != nil {
					writeError(w, 503, "pairing unavailable")
					return
				}
				alphabet := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
				for i, v := range raw {
					if i == 4 {
						code += "-"
					}
					code += string(alphabet[int(v)&31])
				}
				collision := false
				for _, p := range b.pairs {
					if p.Code == code {
						collision = true
					}
				}
				if !collision {
					break
				}
				code = ""
			}
			b.pairs[key] = &browserPair{Secret: key, Code: code, Expires: b.cfg.auth.now().Add(5 * time.Minute)}
			writeJSON(w, 200, map[string]any{"user_code": code, "expires_in": 300, "interval": 3})
			return
		}
		p := b.pairs[key]
		if p == nil {
			writeError(w, 404, "pairing unavailable")
			return
		}
		now := b.cfg.auth.now()
		if now.Before(p.Next) {
			writeError(w, 429, "wait before polling")
			return
		}
		p.Next = now.Add(3 * time.Second)
		p.Polls++
		if p.Polls > 100 {
			delete(b.pairs, key)
			writeError(w, 429, "pairing unavailable")
			return
		}
		if !p.Approved {
			writeJSON(w, 202, map[string]string{"status": "pending"})
			return
		}
		// Remove before minting, while holding the lock: no replay or concurrent double consumption.
		delete(b.pairs, key)
		token, e := b.cfg.auth.store.createBrowser(p.Native, p.Owner, now)
		if e != nil {
			writeError(w, 401, "pairing unavailable")
			return
		}
		browserSetCookie(w, browserCookie, token, 86400)
		browserSetCookie(w, pairingCookie, "", -1)
		writeJSON(w, 200, map[string]string{"status": "approved"})
	default:
		writeError(w, 503, "Apple web Services ID is not configured; use app approval")
	}
}
func (b *browserAuth) allowedStart(r *http.Request) bool {
	clone := r.Clone(r.Context())
	clone.URL.Path = "pairing-create"
	return b.allowed(clone, 5)
}
func (b *browserAuth) native(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if r.Method != "POST" {
		writeError(w, 405, "method not allowed")
		return
	}
	token := bearerSession(r)
	s, e := b.cfg.auth.store.lookup(token, b.cfg.auth.now())
	if e != nil || s.Kind == "browser" || r.Header.Get("Origin") != "" {
		writeError(w, 401, "authentication required")
		return
	}
	if !b.allowed(r, 10) {
		writeError(w, 429, "try later")
		return
	}
	var input struct {
		Code     string `json:"user_code"`
		Approval string `json:"approval_token"`
		Approve  bool   `json:"approve"`
	}
	if !decodeProvider(w, r, &input) {
		return
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	b.clean()
	if strings.HasSuffix(r.URL.Path, "/inspect") {
		code := strings.ToUpper(strings.TrimSpace(input.Code))
		for _, p := range b.pairs {
			if p.Code == code && p.Owner == "" {
				p.Owner = s.UserID
				p.Native = token
				p.Approval = randomAuthToken()
				writeJSON(w, 200, map[string]any{"approval_token": p.Approval, "user_code": p.Code, "origin": b.origin, "expires_at": p.Expires})
				return
			}
		}
	} else {
		for key, p := range b.pairs {
			if p.Approval != "" && constantAuthEqual(p.Approval, input.Approval) && p.Owner == s.UserID && constantAuthEqual(p.Native, token) && !p.Approved {
				p.Approval = ""
				if input.Approve {
					p.Approved = true
				} else {
					delete(b.pairs, key)
				}
				w.WriteHeader(204)
				return
			}
		}
	}
	writeError(w, 404, "pairing unavailable")
}

// Cookie sessions never fall back to shared history or native credentials. The
// bearer header is injected only inside the trusted same-origin server boundary.
func (b *browserAuth) wrap(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/v1/") {
			w.Header().Set("Cache-Control", "no-store")
		}
		if strings.HasPrefix(r.URL.Path, "/v1/auth/") && bearerSession(r) != "" {
			if s, e := b.cfg.auth.store.lookup(bearerSession(r), b.cfg.auth.now()); e == nil && s.Kind == "browser" {
				writeError(w, 401, "native session required")
				return
			}
		}
		if r.URL.Path == "/v1/translations" || r.URL.Path == "/v1/provider" || r.URL.Path == "/v1/provider/connect" || r.URL.Path == "/v1/provider/disconnect" {
			if r.Header.Get("Origin") != "" || cookieValue(r, browserCookie) != "" {
				token := cookieValue(r, browserCookie)
				s, e := b.cfg.auth.store.lookup(token, b.cfg.auth.now())
				if e != nil || s.Kind != "browser" {
					writeError(w, 401, "authentication required")
					return
				}
				if r.Method != "GET" && !b.mutation(w, r, token) {
					return
				}
				r = r.Clone(r.Context())
				r.Header.Set("Authorization", "Bearer "+token)
			}
		}
		next.ServeHTTP(w, r)
	})
}

// Atomic durable mint into the existing hashed session store. Approval remains
// process-local and expires on restart; no native token ever reaches the browser.
func (s *authStore) createBrowser(native, user string, now time.Time) (string, error) {
	token := randomAuthToken()
	err := s.lock.locked(func() error {
		d, e := s.read()
		if e != nil {
			return e
		}
		parent := d.Sessions[sessionHash(native)]
		if parent.UserID != user || parent.Kind == "browser" || !now.Before(parent.Expires) {
			return io.ErrUnexpectedEOF
		}
		d.Sessions[sessionHash(token)] = authSession{UserID: user, Kind: "browser", Expires: now.Add(24 * time.Hour)}
		return s.write(d)
	})
	return token, err
}
