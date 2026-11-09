package main

import (
	"bytes"
	"crypto/rand"
	"crypto/rsa"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type attemptRaceFixture struct {
	t             *testing.T
	h             http.Handler
	cfg           *serverConfig
	session, user string
	nonces        map[string]string
}

func newAttemptRaceFixture(t *testing.T) *attemptRaceFixture {
	t.Helper()
	t.Setenv("PROVIDER_KEY_FILE", t.TempDir()+"/key")
	if err := os.WriteFile(os.Getenv("PROVIDER_KEY_FILE"), bytes.Repeat([]byte("k"), 32), 0600); err != nil {
		t.Fatal(err)
	}
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	f := &attemptRaceFixture{t: t, nonces: map[string]string{}}
	f.cfg = &serverConfig{authPath: t.TempDir() + "/auth.json", historyPath: t.TempDir() + "/history.json"}
	f.cfg.httpClient = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		if strings.HasSuffix(r.URL.Path, "jwks.json") {
			return (jwksTransport{key}).RoundTrip(httptest.NewRequest("GET", appleJWKSURL, nil))
		}
		r.ParseForm()
		code := r.Form.Get("code")
		token := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{"iss": providerIssuer, "aud": "oaiapp_registered", "sub": "subject-" + code, "nonce": f.nonces[code], "exp": time.Now().Add(time.Hour).Unix()})
		token.Header["kid"] = "apple-test"
		raw, err := token.SignedString(key)
		if err != nil {
			return nil, err
		}
		b, _ := json.Marshal(map[string]any{"access_token": "access-" + code, "refresh_token": "refresh-" + code, "id_token": raw, "scope": providerScope, "token_type": "Bearer", "expires_in": 3600})
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(bytes.NewReader(b))}, nil
	})}
	f.h, err = newHandler(f.cfg)
	if err != nil {
		t.Fatal(err)
	}
	var session authSession
	f.session, session, err = f.cfg.auth.store.create("owner", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	f.user = session.UserID
	return f
}
func (f *attemptRaceFixture) connect() string {
	f.t.Helper()
	w := authCall(f.h, "POST", "/v1/provider/connect", "{}", f.session)
	if w.Code != 200 {
		f.t.Fatalf("connect: %d %s", w.Code, w.Body.String())
	}
	return f.code(w)
}
func (f *attemptRaceFixture) code(w *httptest.ResponseRecorder) string {
	f.t.Helper()
	var v struct {
		Token string `json:"bootstrap_token"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil || v.Token == "" {
		f.t.Fatalf("connect response: %s", w.Body.String())
	}
	return v.Token
}
func (f *attemptRaceFixture) start(token, code string) string {
	f.t.Helper()
	b, _ := json.Marshal(map[string]string{"bootstrap_token": token, "redirect_uri": "http://127.0.0.1:45678/auth/callback"})
	w := authCall(f.h, "POST", "/v1/provider/bootstrap/start", string(b), "")
	if w.Code != 200 {
		f.t.Fatalf("start %s: %d %s", code, w.Code, w.Body.String())
	}
	var v struct {
		URL string `json:"authorize_url"`
	}
	json.Unmarshal(w.Body.Bytes(), &v)
	u, err := url.Parse(v.URL)
	if err != nil {
		f.t.Fatal(err)
	}
	f.nonces[code] = u.Query().Get("nonce")
	return "http://127.0.0.1:45678/auth/callback?code=" + code + "&client_id=oaiapp_registered&state=" + url.QueryEscape(u.Query().Get("state"))
}
func (f *attemptRaceFixture) complete(token, callback string) *httptest.ResponseRecorder {
	f.t.Helper()
	b, _ := json.Marshal(map[string]string{"bootstrap_token": token, "callback_url": callback})
	return authCall(f.h, "POST", "/v1/provider/bootstrap/complete", string(b), "")
}

func TestProviderCanceledDelayedConnectDoesNotInvalidateReplacement(t *testing.T) {
	f := newAttemptRaceFixture(t)
	// A has reached the handler but its body is delayed. Canceling the native UI
	// does not guarantee the server sees cancellation: deliberately keep it alive.
	reader, writer := io.Pipe()
	entered, done := make(chan struct{}), make(chan struct{})
	req := httptest.NewRequest("POST", "/v1/provider/connect", nil)
	req.Header.Set("Authorization", "Bearer "+f.session)
	req.Body = &signalingProviderBody{ReadCloser: reader, entered: entered}
	a := httptest.NewRecorder()
	go func() { defer close(done); f.h.ServeHTTP(a, req) }()
	defer func() { writer.Close(); reader.Close(); <-done }()
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("A not suspended")
	}
	// User cancels A, then B issues and starts before A is allowed to issue.
	b := f.connect()
	callback := f.start(b, "B")
	if _, err := writer.Write([]byte("{}")); err != nil {
		t.Fatal(err)
	}
	writer.Close()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("A not released")
	}
	if a.Code != 200 {
		t.Fatalf("delayed A: %d %s", a.Code, a.Body.String())
	}
	if w := f.complete(b, callback); w.Code != 204 {
		t.Fatalf("B invalidated by delayed canceled A: %d %s", w.Code, w.Body.String())
	}
	c, err := f.cfg.provider.load(f.user)
	if err != nil || c.AccessToken != "access-B" {
		t.Fatalf("B not persisted: %v", err)
	}
	// Issuing A never consumed it either; it cannot replace B's committed identity.
	if f.code(a) == b {
		t.Fatal("attempts share token")
	}
	ca := f.start(f.code(a), "A")
	if w := f.complete(f.code(a), ca); w.Code != 409 {
		t.Fatalf("delayed A replaced B: %d %s", w.Code, w.Body.String())
	}
}

func TestProviderSiblingCompletionCannotReplaceCommittedIdentity(t *testing.T) {
	f := newAttemptRaceFixture(t)
	a := f.connect()
	ca := f.start(a, "A")
	b := f.connect()
	cb := f.start(b, "B")
	if w := f.complete(b, cb); w.Code != 204 {
		t.Fatalf("B complete: %d %s", w.Code, w.Body.String())
	}
	if w := f.complete(a, ca); w.Code != 409 {
		t.Fatalf("stale A replaced B: %d %s", w.Code, w.Body.String())
	}
	c, err := f.cfg.provider.load(f.user)
	if err != nil || c.Subject != "subject-B" || c.AccessToken != "access-B" {
		t.Fatalf("B identity replaced: %v", err)
	}
}

func TestProviderAttemptCapacityRejectsWithoutEvictionAndReclaimsExpiry(t *testing.T) {
	f := newAttemptRaceFixture(t)
	// Seed attempts to isolate capacity from the independent minute rate limit.
	p := f.cfg.provider
	p.mu.Lock()
	for i := 0; i < 8; i++ {
		p.attempts[sessionHash(string(rune('a'+i)))] = providerAttempt{User: f.user, Session: f.session, Expires: time.Now().Add(time.Minute)}
	}
	p.attempts["other"] = providerAttempt{User: "other", Expires: time.Now().Add(time.Minute)}
	p.mu.Unlock()
	w := authCall(f.h, "POST", "/v1/provider/connect", "{}", f.session)
	if w.Code != 429 {
		t.Fatalf("owner cap: %d", w.Code)
	}
	p.mu.Lock()
	if len(p.attempts) != 9 {
		t.Error("capacity evicted live attempts")
	}
	a := p.attempts[sessionHash("a")]
	a.Expires = time.Now().Add(-time.Second)
	p.attempts[sessionHash("a")] = a
	p.mu.Unlock()
	f.connect()
	p.mu.Lock()
	defer p.mu.Unlock()
	if len(p.attempts) != 9 {
		t.Errorf("expired slot not reclaimed: %d", len(p.attempts))
	}
	if _, ok := p.attempts["other"]; !ok {
		t.Error("unrelated owner removed")
	}
	if _, ok := p.attempts[sessionHash("a")]; ok {
		t.Error("expired attempt retained")
	}
}
