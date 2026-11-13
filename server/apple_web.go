package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"mime"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// This registered return URL is deliberately not derived from Host or proxy headers.
const appleWebCallback = "https://keinemagie.tinyserve.org/v1/auth/apple/callback"
const appleWebOrigin = "https://keinemagie.tinyserve.org"
const appleTransactionCookie = "__Host-km-apple"

type appleWebTransaction struct {
	state, nonce string
	expires      time.Time
	used         bool
}
type appleWeb struct {
	browser                 *browserAuth
	clientID, teamID, keyID string
	key                     *ecdsa.PrivateKey
	verifier                *appleAuth
	mu                      sync.Mutex
	transactions            map[string]*appleWebTransaction
}

func newAppleWeb(b *browserAuth) (*appleWeb, error) {
	id, team, kid, path := os.Getenv("APPLE_WEB_CLIENT_ID"), os.Getenv("APPLE_TEAM_ID"), os.Getenv("APPLE_KEY_ID"), os.Getenv("APPLE_PRIVATE_KEY_FILE")
	// Incomplete registration is not advertised; pairing remains available.
	if id == "" || team == "" || kid == "" || path == "" {
		return nil, nil
	}
	if b.origin != appleWebOrigin || id == b.cfg.auth.clientID || !regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9.-]{1,254}$`).MatchString(id) || !regexp.MustCompile(`^[A-Z0-9]{10}$`).MatchString(team) || !regexp.MustCompile(`^[A-Z0-9]{10}$`).MatchString(kid) {
		return nil, errors.New("invalid Apple web registration")
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, errors.New("Apple private key unavailable")
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 || info.Size() > 16384 {
		return nil, errors.New("Apple private key must be a private regular file (0600)")
	}
	raw, err := io.ReadAll(io.LimitReader(f, 16385))
	if err != nil {
		return nil, errors.New("Apple private key unreadable")
	}
	block, rest := pem.Decode(raw)
	if block == nil || block.Type != "PRIVATE KEY" || strings.TrimSpace(string(rest)) != "" {
		return nil, errors.New("invalid Apple PKCS8 key")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, errors.New("invalid Apple PKCS8 key")
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok || key.Curve != elliptic.P256() {
		return nil, errors.New("Apple key must use P-256")
	}
	verifier := &appleAuth{keys: b.cfg.auth.keys, clientID: id, now: b.cfg.auth.now}
	return &appleWeb{browser: b, clientID: id, teamID: team, keyID: kid, key: key, verifier: verifier, transactions: map[string]*appleWebTransaction{}}, nil
}
func appleTransactionSetCookie(w http.ResponseWriter, value string, age int) {
	http.SetCookie(w, &http.Cookie{Name: appleTransactionCookie, Value: value, Path: "/", Secure: true, HttpOnly: true, SameSite: http.SameSiteNoneMode, MaxAge: age})
}
func (a *appleWeb) cancel(r *http.Request) {
	a.mu.Lock()
	defer a.mu.Unlock()
	delete(a.transactions, sessionHash(cookieValue(r, appleTransactionCookie)))
}
func (b *browserAuth) appleHandle(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Referrer-Policy", "no-referrer")
	if r.Method != "POST" {
		writeError(w, 405, "method not allowed")
		return
	}
	if b.apple == nil {
		writeError(w, 503, "Apple web sign-in is not configured")
		return
	}
	if r.URL.RawQuery != "" {
		writeError(w, 400, "invalid request")
		return
	}
	if r.URL.Path == "/v1/auth/apple/start" {
		b.apple.start(w, r)
		return
	}
	b.apple.callback(w, r)
}
func (a *appleWeb) start(w http.ResponseWriter, r *http.Request) {
	b := a.browser
	if !b.mutation(w, r, cookieValue(r, pairingCookie)) {
		return
	}
	if r.Header.Get("Sec-Fetch-Site") == "cross-site" {
		writeError(w, 403, "browser request denied")
		return
	}
	if !b.allowed(r, 10) {
		writeError(w, 429, "try later")
		return
	}
	now := b.cfg.auth.now()
	secret := randomAuthToken()
	tx := &appleWebTransaction{state: randomAuthToken(), nonce: randomAuthToken(), expires: now.Add(5 * time.Minute)}
	a.mu.Lock()
	for k, v := range a.transactions {
		if !now.Before(v.expires) {
			delete(a.transactions, k)
		}
	}
	if len(a.transactions) >= 1024 {
		a.mu.Unlock()
		writeError(w, 429, "try later")
		return
	}
	delete(a.transactions, sessionHash(cookieValue(r, appleTransactionCookie)))
	a.transactions[sessionHash(secret)] = tx
	a.mu.Unlock()
	appleTransactionSetCookie(w, secret, 300)
	q := url.Values{"client_id": {a.clientID}, "redirect_uri": {appleWebCallback}, "response_type": {"code"}, "response_mode": {"form_post"}, "state": {tx.state}, "nonce": {tx.nonce}}
	// Apple's published authorize/token contract and discovery do not advertise PKCE.
	// Do not send an unsupported verifier/challenge and imply that Apple enforced it.
	writeJSON(w, 200, map[string]string{"authorization_url": "https://appleid.apple.com/auth/authorize?" + q.Encode()})
}
func (a *appleWeb) exchange(ctx context.Context, code string) (string, error) {
	now := a.browser.cfg.auth.now()
	secret := jwt.NewWithClaims(jwt.SigningMethodES256, jwt.MapClaims{"iss": a.teamID, "sub": a.clientID, "aud": "https://appleid.apple.com", "iat": now.Unix(), "exp": now.Add(5 * time.Minute).Unix()})
	secret.Header["kid"] = a.keyID
	signed, err := secret.SignedString(a.key)
	if err != nil {
		return "", err
	}
	form := url.Values{"client_id": {a.clientID}, "client_secret": {signed}, "code": {code}, "grant_type": {"authorization_code"}, "redirect_uri": {appleWebCallback}}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, "POST", "https://appleid.apple.com/auth/token", strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := a.verifier.keys.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 65537))
	if err != nil || len(raw) > 65536 || resp.StatusCode != 200 {
		return "", errors.New("Apple exchange failed")
	}
	var result struct {
		IDToken string `json:"id_token"`
	}
	if json.Unmarshal(raw, &result) != nil || result.IDToken == "" {
		return "", errors.New("Apple token unavailable")
	}
	return result.IDToken, nil
}
func (a *appleWeb) callback(w http.ResponseWriter, r *http.Request) {
	// Only this exact callback accepts Apple's cross-site form POST. Origin is
	// not authentication: the browser secret, state, code exchange and signed
	// nonce-bearing token are all required. No ambient session is trusted here.
	if o := r.Header.Get("Origin"); o != "" && o != "https://appleid.apple.com" {
		writeError(w, 403, "browser request denied")
		return
	}
	if !a.browser.allowed(r, 60) {
		writeError(w, 429, "try later")
		return
	}
	media, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || media != "application/x-www-form-urlencoded" {
		writeError(w, 400, "invalid request")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 16384)
	defer r.Body.Close()
	if r.ParseForm() != nil {
		writeError(w, 400, "invalid request")
		return
	}
	for _, key := range []string{"state", "code", "error"} {
		if len(r.PostForm[key]) > 1 {
			writeError(w, 400, "invalid request")
			return
		}
	}
	key := sessionHash(cookieValue(r, appleTransactionCookie))
	a.mu.Lock()
	tx := a.transactions[key]
	if tx == nil || tx.used || !a.browser.cfg.auth.now().Before(tx.expires) || !constantAuthEqual(tx.state, r.PostForm.Get("state")) {
		a.mu.Unlock()
		writeError(w, 401, "authentication failed")
		return
	}
	tx.used = true
	a.mu.Unlock()
	defer func() {
		a.mu.Lock()
		if a.transactions[key] == tx {
			delete(a.transactions, key)
		}
		a.mu.Unlock()
	}()
	appleTransactionSetCookie(w, "", -1)
	if r.PostForm.Get("error") != "" || r.PostForm.Get("code") == "" {
		writeError(w, 401, "authentication failed")
		return
	}
	raw, err := a.exchange(r.Context(), r.PostForm.Get("code"))
	if err != nil {
		writeError(w, 401, "authentication failed")
		return
	}
	// The verifier is separate from native auth: the native audience is unchanged.
	verifier := &appleAuth{keys: a.verifier.keys, clientID: a.clientID, now: a.browser.cfg.auth.now}
	sub, err := verifier.verify(r.Context(), raw, appleChallenge{Nonce: tx.nonce})
	if err != nil {
		writeError(w, 401, "authentication failed")
		return
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.transactions[key] != tx || !a.browser.cfg.auth.now().Before(tx.expires) || r.Context().Err() != nil {
		writeError(w, 401, "authentication failed")
		return
	}
	token, _, err := a.browser.cfg.auth.store.createKind(sub, a.browser.cfg.auth.now(), "browser")
	if err != nil {
		writeError(w, 503, "authentication unavailable")
		return
	}
	browserSetCookie(w, browserCookie, token, int(browserSessionLifetime/time.Second))
	browserSetCookie(w, pairingCookie, "", -1)
	http.Redirect(w, r, "/", http.StatusSeeOther)
}
