package main

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const providerIssuer = "https://auth.openai.com"
const providerScope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"

type providerCredential struct {
	ClientID     string    `json:"client_id"`
	Subject      string    `json:"subject"`
	AccessToken  string    `json:"access_token"`
	RefreshToken string    `json:"refresh_token"`
	IDToken      string    `json:"id_token"`
	Scope        string    `json:"scope"`
	TokenType    string    `json:"token_type"`
	ExpiresIn    int       `json:"expires_in"`
	Expires      time.Time `json:"expires_at"`
	ConnectionID string    `json:"connection_id,omitempty"`
}
type providerAttempt struct {
	User, Session, State, Nonce, Verifier, Redirect, ClientID, Subject string
	BaseConnectionID                                                   string
	Expires                                                            time.Time
}
type providerService struct {
	mu        sync.Mutex
	owners    map[string]*providerOwnerLock
	cfg       *serverConfig
	attempts  map[string]providerAttempt
	rates     map[string]authRate
	key       []byte
	dir, host string
	client    *http.Client
}

type providerOwnerLock struct {
	ready chan struct{}
	users int
}

// Lock only this owner's credentials; canceled waiters stop promptly and idle
// entries are removed rather than growing with every account ever seen.
func (p *providerService) lockOwner(ctx context.Context, user string) (func(), error) {
	p.mu.Lock()
	if p.owners == nil {
		p.owners = make(map[string]*providerOwnerLock)
	}
	l := p.owners[user]
	if l == nil {
		l = &providerOwnerLock{ready: make(chan struct{}, 1)}
		p.owners[user] = l
	}
	l.users++
	p.mu.Unlock()
	cleanup := func() {
		p.mu.Lock()
		defer p.mu.Unlock()
		l.users--
		if l.users == 0 {
			delete(p.owners, user)
		}
	}
	select {
	case l.ready <- struct{}{}:
		if err := ctx.Err(); err != nil {
			<-l.ready
			cleanup()
			return nil, err
		}
		return func() { <-l.ready; cleanup() }, nil
	case <-ctx.Done():
		cleanup()
		return nil, ctx.Err()
	}
}

func newProvider(cfg *serverConfig) (*providerService, error) {
	p := &providerService{cfg: cfg, attempts: map[string]providerAttempt{}, rates: map[string]authRate{}, dir: filepath.Join(filepath.Dir(cfg.auth.store.lock.path), "providers")}
	client := cfg.httpClient
	if client == nil {
		client = &http.Client{Timeout: 90 * time.Second}
	}
	clone := *client
	clone.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	p.client = &clone
	keyPath := os.Getenv("PROVIDER_KEY_FILE")
	if keyPath == "" {
		return p, nil
	}
	if filepath.Dir(keyPath) == p.dir {
		return nil, errors.New("provider key must be separate from provider data")
	}
	info, err := os.Stat(keyPath)
	if err != nil {
		return nil, err
	}
	if info.Mode().Perm()&0077 != 0 {
		return nil, errors.New("provider key must have owner-only permissions")
	}
	p.key, err = os.ReadFile(keyPath)
	if err != nil {
		return nil, err
	}
	if len(p.key) != 32 {
		return nil, errors.New("provider key must contain exactly 32 raw bytes")
	}
	lock := &historyStore{path: filepath.Join(p.dir, "host")}
	err = lock.locked(func() error {
		b, e := os.ReadFile(lock.path)
		// Earlier versions mislabeled a 32-byte base64url token as a UUID.
		// Migrate only that exact legacy shape, preserving established hosts.
		legacy := false
		if strings.HasPrefix(string(b), "urn:uuid:") {
			raw := strings.TrimPrefix(string(b), "urn:uuid:")
			decoded, err := base64.RawURLEncoding.DecodeString(raw)
			legacy = err == nil && len(decoded) == 32 && base64.RawURLEncoding.EncodeToString(decoded) == raw
		}
		if os.IsNotExist(e) || (e == nil && legacy) {
			var id [16]byte
			if _, e = rand.Read(id[:]); e != nil {
				return e
			}
			id[6] = (id[6] & 0x0f) | 0x40
			id[8] = (id[8] & 0x3f) | 0x80
			b = []byte(fmt.Sprintf("urn:uuid:%x-%x-%x-%x-%x", id[0:4], id[4:6], id[6:8], id[8:10], id[10:16]))
			f, err := os.CreateTemp(p.dir, ".host-*")
			if err != nil {
				return err
			}
			defer os.Remove(f.Name())
			if _, err = f.Write(b); err == nil {
				err = f.Sync()
			}
			closeErr := f.Close()
			if err != nil {
				return err
			}
			if closeErr != nil {
				return closeErr
			}
			if e = os.Rename(f.Name(), lock.path); e != nil {
				return e
			}
		}
		p.host = string(b)
		return e
	})
	return p, err
}
func (p *providerService) credentialPath(user string) string {
	return filepath.Join(p.dir, sessionHash(user)+".enc")
}
func (p *providerService) load(user string) (providerCredential, error) {
	var c providerCredential
	if len(p.key) != 32 {
		return c, errors.New("setup required")
	}
	b, err := os.ReadFile(p.credentialPath(user))
	if err != nil {
		return c, err
	}
	block, _ := aes.NewCipher(p.key)
	g, _ := cipher.NewGCM(block)
	if len(b) < g.NonceSize() {
		return c, errors.New("invalid encrypted credential")
	}
	clear, err := g.Open(nil, b[:g.NonceSize()], b[g.NonceSize():], []byte(user))
	if err != nil {
		return c, err
	}
	err = json.Unmarshal(clear, &c)
	return c, err
}
func (p *providerService) save(user string, c providerCredential) error {
	block, err := aes.NewCipher(p.key)
	if err != nil {
		return err
	}
	g, err := cipher.NewGCM(block)
	if err != nil {
		return err
	}
	nonce := make([]byte, g.NonceSize())
	if _, err = rand.Read(nonce); err != nil {
		return err
	}
	clear, err := json.Marshal(c)
	if err != nil {
		return err
	}
	b := g.Seal(nonce, nonce, clear, []byte(user))
	if err = os.MkdirAll(p.dir, 0700); err != nil {
		return err
	}
	f, err := os.CreateTemp(p.dir, ".credential-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	defer f.Close()
	if _, err = f.Write(b); err != nil {
		return err
	}
	if err = f.Sync(); err != nil {
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	if err = os.Rename(f.Name(), p.credentialPath(user)); err != nil {
		return err
	}
	directory, err := os.Open(p.dir)
	if err != nil {
		return err
	}
	defer directory.Close()
	return directory.Sync()
}
func (p *providerService) owner(w http.ResponseWriter, r *http.Request) (string, bool) {
	w.Header().Set("Cache-Control", "no-store")
	s, err := p.cfg.auth.store.lookup(bearerSession(r), time.Now())
	if err != nil {
		writeError(w, 401, "authentication failed")
		return "", false
	}
	return s.UserID, true
}
func decodeProvider(w http.ResponseWriter, r *http.Request, v any) bool {
	defer r.Body.Close()
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16384))
	d.DisallowUnknownFields()
	if d.Decode(v) != nil || d.Decode(new(any)) != io.EOF {
		writeError(w, 400, "invalid request")
		return false
	}
	return true
}
func (p *providerService) allow(user string, limit int) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	now := time.Now()
	for k, v := range p.rates {
		if now.Sub(v.start) >= time.Minute {
			delete(p.rates, k)
		}
	}
	v := p.rates[user]
	if v.start.IsZero() {
		if len(p.rates) >= 2048 {
			return false
		}
		v.start = now
	}
	if v.count >= limit {
		return false
	}
	v.count++
	p.rates[user] = v
	return true
}
func (p *providerService) handle(w http.ResponseWriter, r *http.Request) {
	user, ok := p.owner(w, r)
	if !ok {
		return
	}
	// Never hold provider locks while waiting for client-controlled input.
	if r.URL.Path == "/v1/provider/connect" && r.Method == "POST" {
		var body struct{}
		if !decodeProvider(w, r, &body) {
			return
		}
	}
	release, err := p.lockOwner(r.Context(), user)
	if err != nil {
		writeError(w, 408, "request canceled")
		return
	}
	defer release()
	if !p.allow(user+"provider", 30) {
		writeError(w, 429, "provider rate limited")
		return
	}
	switch r.URL.Path {
	case "/v1/provider":
		if r.Method != "GET" {
			writeError(w, 405, "method not allowed")
			return
		}
		status := "not_connected"
		message := "Connect your ChatGPT account using the local desktop bootstrap."
		if len(p.key) != 32 {
			status = "setup_required"
			message = "Server administrator must configure PROVIDER_KEY_FILE (32 raw bytes, mode 0600), separate from provider data."
		}
		if stored, err := p.load(user); err == nil && stored.AccessToken != "" {
			c, err := p.access(r.Context(), user)
			if err != nil {
				writeJSON(w, 200, map[string]any{"connected": false, "status": "reauthorization_required", "message": "Reconnect ChatGPT; refresh failed."})
				return
			}
			models, err := p.models(r.Context(), c.AccessToken)
			if err != nil {
				writeError(w, 502, "model catalog unavailable")
				return
			}
			writeJSON(w, 200, map[string]any{"connected": true, "status": "connected", "message": "ChatGPT connected", "models": models, "selected_model": chooseModel(models)})
			return
		}
		writeJSON(w, 200, map[string]any{"connected": false, "status": status, "message": message})
	case "/v1/provider/connect":
		if r.Method != "POST" {
			writeError(w, 405, "method not allowed")
			return
		}
		if len(p.key) != 32 {
			writeError(w, 503, "provider setup required: configure PROVIDER_KEY_FILE")
			return
		}
		if !p.allow(user+"connect", 5) {
			writeError(w, 429, "connection rate limited")
			return
		}
		baseline, loadErr := p.load(user)
		if loadErr != nil && !os.IsNotExist(loadErr) {
			writeError(w, 503, "connection storage unavailable")
			return
		}
		p.mu.Lock()
		ownerAttempts := 0
		for k, v := range p.attempts {
			if !time.Now().Before(v.Expires) {
				delete(p.attempts, k)
			} else if v.User == user {
				ownerAttempts++
			}
		}
		// A canceled client request can still arrive after its replacement.
		// Never evict live flows on issuance; reject excess attempts instead.
		if len(p.attempts) >= 1024 || ownerAttempts >= 8 {
			p.mu.Unlock()
			writeError(w, 429, "connection unavailable")
			return
		}
		token := randomAuthToken()
		p.attempts[sessionHash(token)] = providerAttempt{User: user, Session: bearerSession(r), BaseConnectionID: baseline.ConnectionID, Expires: time.Now().Add(5 * time.Minute)}
		p.mu.Unlock()
		writeJSON(w, 200, map[string]any{"bootstrap_token": token, "expires_in": 300, "message": "On your desktop run: cd server && go run . connect. Enter this server URL and one-time code. Continue with ChatGPT in the browser; credentials stay on your server."})
	case "/v1/provider/disconnect":
		if r.Method != "POST" {
			writeError(w, 405, "method not allowed")
			return
		}
		c, loadErr := p.load(user)
		remoteConfirmed := true
		if loadErr == nil {
			if c.RefreshToken != "" {
				remoteConfirmed = p.revoke(r.Context(), c) == nil
			}
			c.AccessToken = ""
			c.RefreshToken = ""
			c.IDToken = ""
			c.Scope = ""
			c.Expires = time.Time{}
			if err := p.save(user, c); err != nil {
				writeError(w, 503, "disconnect unavailable")
				return
			}
		} else if !os.IsNotExist(loadErr) {
			if len(p.key) == 32 {
				writeError(w, 503, "disconnect unavailable")
				return
			}
			// Without a key we cannot revoke or preserve registration metadata,
			// but must still durably remove credentials before reporting success.
			remoteConfirmed = false
			if err := os.Remove(p.credentialPath(user)); err != nil && !os.IsNotExist(err) {
				writeError(w, 503, "disconnect unavailable")
				return
			}
			if directory, err := os.Open(p.dir); err == nil {
				err = directory.Sync()
				directory.Close()
				if err != nil {
					writeError(w, 503, "disconnect unavailable")
					return
				}
			} else if !os.IsNotExist(err) {
				writeError(w, 503, "disconnect unavailable")
				return
			}
		}
		if !remoteConfirmed {
			w.Header().Set("X-Revocation-Status", "unconfirmed")
		}
		p.mu.Lock()
		for k, v := range p.attempts {
			if v.User == user {
				delete(p.attempts, k)
			}
		}
		p.mu.Unlock()
		if !remoteConfirmed {
			writeJSON(w, 200, map[string]any{"connected": false, "revoked": false, "message": "Disconnected locally. Upstream revocation is unconfirmed; disconnect this app in ChatGPT Settings as well."})
			return
		}
		w.WriteHeader(204)
	default:
		writeError(w, 404, "not found")
	}
}
func validLoopback(raw string) bool {
	u, e := url.Parse(raw)
	return e == nil && u.Scheme == "http" && u.Hostname() == "127.0.0.1" && u.Port() != "" && u.Path == "/auth/callback" && u.RawQuery == "" && u.Fragment == "" && u.User == nil
}
func (p *providerService) bootstrap(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if r.Method != "POST" {
		writeError(w, 405, "method not allowed")
		return
	}
	var body struct {
		Token    string `json:"bootstrap_token"`
		Redirect string `json:"redirect_uri"`
		Callback string `json:"callback_url"`
	}
	if !decodeProvider(w, r, &body) {
		return
	}
	key := sessionHash(body.Token)
	p.mu.Lock()
	a := p.attempts[key]
	p.mu.Unlock()
	release, err := p.lockOwner(r.Context(), a.User)
	if err != nil {
		writeError(w, 408, "request canceled")
		return
	}
	defer release()
	p.mu.Lock()
	a, ok := p.attempts[key]
	if !ok || !time.Now().Before(a.Expires) {
		delete(p.attempts, key)
		p.mu.Unlock()
		writeError(w, 401, "connection attempt expired")
		return
	}
	if _, err := p.cfg.auth.store.lookup(a.Session, time.Now()); err != nil {
		delete(p.attempts, key)
		p.mu.Unlock()
		writeError(w, 401, "authentication failed")
		return
	}
	if strings.HasSuffix(r.URL.Path, "/start") {
		if !validLoopback(body.Redirect) || a.Redirect != "" {
			p.mu.Unlock()
			writeError(w, 400, "exact HTTP 127.0.0.1 callback required")
			return
		}
		a.Redirect = body.Redirect
		a.State = randomAuthToken()
		a.Nonce = randomAuthToken()
		a.Verifier = randomAuthToken()
		clientID := "dynamic_agent_client"
		q := url.Values{}
		if c, e := p.load(a.User); e == nil {
			a.ClientID = c.ClientID
			a.Subject = c.Subject
			clientID = c.ClientID
			q.Set("id_token_hint", c.IDToken)
		} else {
			q.Set("agent_name_hint", "KeineMagie")
		}
		p.attempts[key] = a
		p.mu.Unlock()
		sum := sha256.Sum256([]byte(a.Verifier))
		for k, v := range map[string]string{"client_id": clientID, "ext_agent_host_id": p.host, "response_type": "code", "redirect_uri": a.Redirect, "scope": providerScope, "resource": "https://api.openai.com/v1", "state": a.State, "nonce": a.Nonce, "code_challenge_method": "S256", "code_challenge": base64.RawURLEncoding.EncodeToString(sum[:])} {
			q.Set(k, v)
		}
		writeJSON(w, 200, map[string]string{"authorize_url": providerIssuer + "/api/accounts/authorize?" + q.Encode()})
		return
	}
	delete(p.attempts, key)
	p.mu.Unlock()
	cb, err := url.Parse(body.Callback)
	if err != nil || a.Redirect == "" {
		writeError(w, 400, "invalid callback")
		return
	}
	base := *cb
	base.RawQuery = ""
	base.Fragment = ""
	q := cb.Query()
	if base.String() != a.Redirect || cb.Fragment != "" || len(q["state"]) != 1 || !constantAuthEqual(q.Get("state"), a.State) || q.Get("error") != "" {
		writeError(w, 400, "authorization denied or invalid state")
		return
	}
	// Issuance is not an ordering signal: a canceled request may arrive late.
	// Commit only against the connection present when this attempt was issued.
	// Owner locking makes this compare-and-save atomic with other completions.
	current, loadErr := p.load(a.User)
	if loadErr != nil && !os.IsNotExist(loadErr) {
		writeError(w, 503, "connection storage unavailable")
		return
	}
	if current.ConnectionID != a.BaseConnectionID {
		writeError(w, 409, "connection changed; start a new connection")
		return
	}
	id := a.ClientID
	if id == "" {
		id = q.Get("client_id")
	} else if q.Get("client_id") != "" && q.Get("client_id") != id {
		writeError(w, 400, "registration mismatch")
		return
	}
	if !strings.HasPrefix(id, "oaiapp_") || q.Get("code") == "" {
		writeError(w, 400, "registration incomplete")
		return
	}
	c, err := p.token(r.Context(), url.Values{"grant_type": {"authorization_code"}, "client_id": {id}, "code": {q.Get("code")}, "code_verifier": {a.Verifier}, "redirect_uri": {a.Redirect}, "resource": {"https://api.openai.com/v1"}})
	if err != nil {
		writeError(w, 502, "ChatGPT authorization exchange failed; start a new connection")
		return
	}
	c.ClientID = id
	sub, err := p.verify(r.Context(), c.IDToken, id, a.Nonce)
	if err != nil || (a.Subject != "" && sub != a.Subject) || !hasScope(c.Scope, "chatgpt.tokens.use.direct") {
		writeError(w, 400, "ChatGPT identity or plan permission invalid")
		return
	}
	c.Subject = sub
	c.ConnectionID = randomAuthToken()
	if _, err = p.cfg.auth.store.lookup(a.Session, time.Now()); err != nil {
		writeError(w, 401, "authentication failed")
		return
	}
	if err = p.save(a.User, c); err != nil {
		writeError(w, 503, "connection storage unavailable")
		return
	}
	w.WriteHeader(204)
}
func (p *providerService) revoke(ctx context.Context, c providerCredential) error {
	req, _ := http.NewRequestWithContext(ctx, "GET", providerIssuer+"/.well-known/openid-configuration", nil)
	resp, err := p.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return errors.New("discovery unavailable")
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, 65537))
	if err != nil || len(b) > 65536 {
		return errors.New("invalid discovery")
	}
	var discovery struct {
		Endpoint string `json:"revocation_endpoint"`
	}
	if json.Unmarshal(b, &discovery) != nil {
		return errors.New("invalid discovery")
	}
	endpoint, err := url.Parse(discovery.Endpoint)
	if err != nil || endpoint.Scheme != "https" || endpoint.Host != "auth.openai.com" || endpoint.User != nil {
		return errors.New("untrusted revocation endpoint")
	}
	values := url.Values{"token": {c.RefreshToken}, "token_type_hint": {"refresh_token"}, "client_id": {c.ClientID}}
	req, _ = http.NewRequestWithContext(ctx, "POST", endpoint.String(), strings.NewReader(values.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	revoked, err := p.client.Do(req)
	if err != nil {
		return err
	}
	defer revoked.Body.Close()
	if revoked.StatusCode != 200 {
		return errors.New("revocation unconfirmed")
	}
	return nil
}

func hasScope(scope, want string) bool {
	for _, s := range strings.Fields(scope) {
		if s == want {
			return true
		}
	}
	return false
}
func (p *providerService) token(ctx context.Context, v url.Values) (providerCredential, error) {
	var c providerCredential
	req, _ := http.NewRequestWithContext(ctx, "POST", providerIssuer+"/api/accounts/oauth/token", strings.NewReader(v.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := p.client.Do(req)
	if err != nil {
		return c, err
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(io.LimitReader(resp.Body, 65537))
	if err != nil || len(b) > 65536 || resp.StatusCode != 200 {
		return c, errors.New("token exchange failed")
	}
	if err = json.Unmarshal(b, &c); err != nil {
		return c, err
	}
	if c.AccessToken == "" || c.ExpiresIn <= 0 || !strings.EqualFold(c.TokenType, "Bearer") {
		return c, errors.New("invalid token grant")
	}
	c.Expires = time.Now().Add(time.Duration(c.ExpiresIn) * time.Second)
	return c, nil
}
func (p *providerService) access(ctx context.Context, user string) (providerCredential, error) {
	c, err := p.load(user)
	if err != nil {
		return c, err
	}
	if time.Until(c.Expires) > time.Minute {
		return c, nil
	}
	if c.RefreshToken == "" {
		return c, errors.New("reauthorization required")
	}
	n, err := p.token(ctx, url.Values{"grant_type": {"refresh_token"}, "client_id": {c.ClientID}, "refresh_token": {c.RefreshToken}, "resource": {"https://api.openai.com/v1"}})
	if err != nil {
		return c, err
	}
	if n.Scope == "" {
		n.Scope = c.Scope
	}
	if !hasScope(n.Scope, "chatgpt.tokens.use.direct") {
		return c, errors.New("plan permission missing")
	}
	if n.IDToken != "" {
		sub, e := p.verify(ctx, n.IDToken, c.ClientID, "")
		if e != nil || sub != c.Subject {
			return c, errors.New("refreshed identity mismatch")
		}
	} else {
		n.IDToken = c.IDToken
	}
	if n.RefreshToken == "" {
		n.RefreshToken = c.RefreshToken
	}
	n.ClientID = c.ClientID
	n.Subject = c.Subject
	n.ConnectionID = c.ConnectionID
	return n, p.save(user, n)
}
func (p *providerService) verify(ctx context.Context, raw, id, nonce string) (string, error) {
	req, _ := http.NewRequestWithContext(ctx, "GET", providerIssuer+"/.well-known/jwks.json", nil)
	resp, err := p.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return "", errors.New("keys unavailable")
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, (1<<20)+1))
	if err != nil || len(b) > 1<<20 {
		return "", errors.New("invalid keys")
	}
	// Reuse the already hardened RSA JWKS parser with a fixed trusted response.
	keys := &appleKeys{client: &http.Client{Transport: transportProviderKeys{b}}}
	claims := jwt.MapClaims{}
	_, err = jwt.ParseWithClaims(raw, claims, func(t *jwt.Token) (any, error) {
		kid, _ := t.Header["kid"].(string)
		if kid == "" || len(kid) > 256 {
			return nil, errors.New("invalid key")
		}
		return keys.key(ctx, kid, time.Now())
	}, jwt.WithValidMethods([]string{"RS256"}), jwt.WithIssuer(providerIssuer), jwt.WithAudience(id), jwt.WithExpirationRequired(), jwt.WithIssuedAt())
	if err != nil {
		return "", err
	}
	sub, _ := claims.GetSubject()
	if strings.TrimSpace(sub) == "" {
		return "", errors.New("invalid subject")
	}
	if nonce != "" {
		n, _ := claims["nonce"].(string)
		if !constantAuthEqual(n, nonce) {
			return "", errors.New("invalid nonce")
		}
	}
	return sub, nil
}

type transportProviderKeys struct{ b []byte }

func (t transportProviderKeys) RoundTrip(*http.Request) (*http.Response, error) {
	return &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(t.b)), Header: http.Header{}}, nil
}

type providerModel struct {
	Slug        string `json:"slug"`
	DisplayName string `json:"display_name"`
	Visibility  string `json:"visibility,omitempty"`
}

func (p *providerService) models(ctx context.Context, token string) ([]providerModel, error) {
	req, _ := http.NewRequestWithContext(ctx, "GET", "https://api.openai.com/v1/models", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := p.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("catalog status %d", resp.StatusCode)
	}
	var doc struct {
		Models []providerModel `json:"models"`
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, (1<<20)+1))
	if err != nil || len(b) > 1<<20 {
		return nil, errors.New("catalog too large")
	}
	if err = json.Unmarshal(b, &doc); err != nil {
		return nil, err
	}
	models := []providerModel{}
	for _, m := range doc.Models {
		if m.Visibility == "list" && m.Slug != "" {
			models = append(models, m)
		}
	}
	if len(models) == 0 {
		return nil, errors.New("no available models")
	}
	return models, nil
}
func chooseModel(models []providerModel) string {
	for _, m := range models {
		if m.Slug == "gpt-6-luna" {
			return m.Slug
		}
	}
	if len(models) > 0 {
		return models[0].Slug
	}
	return ""
}
