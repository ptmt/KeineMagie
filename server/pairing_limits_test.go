package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestPairingDenyExpiryRevocationAndBounds(t *testing.T) {
	t.Setenv("WEB_ORIGIN", "https://example.com")
	cfg := &serverConfig{authPath: t.TempDir() + "/auth.json", historyPath: t.TempDir() + "/history.json"}
	_, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	b := newBrowserAuth(cfg)
	clock := time.Now()
	cfg.auth.now = func() time.Time { return clock }
	token, owner, _ := cfg.auth.store.create("alice", clock)
	secret := randomAuthToken()
	key := sessionHash(secret)
	native := func(path, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest("POST", path, strings.NewReader(body))
		r.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		b.native(w, r)
		return w
	}
	pair := func() *browserPair {
		p := &browserPair{Secret: key, Code: "ABCD-EFGH", Expires: clock.Add(5 * time.Minute)}
		b.pairs[key] = p
		return p
	}
	p := pair()
	w := native("/v1/auth/browser/inspect", `{"user_code":"ABCD-EFGH"}`)
	var preview map[string]any
	json.Unmarshal(w.Body.Bytes(), &preview)
	w = native("/v1/auth/browser/approve", `{"approval_token":"`+preview["approval_token"].(string)+`","approve":false}`)
	if w.Code != 204 || b.pairs[key] != nil {
		t.Fatal("denial not consumed")
	}
	p = pair()
	p.Owner = owner.UserID
	p.Native = token
	p.Approved = true
	cfg.auth.store.revoke(token, clock)
	r := httptest.NewRequest("POST", "/v1/web/pairing/poll", strings.NewReader("{}"))
	r.Header.Set("Origin", "https://example.com")
	r.Header.Set("X-CSRF-Token", browserCSRF(secret))
	r.AddCookie(&http.Cookie{Name: pairingCookie, Value: secret})
	w = httptest.NewRecorder()
	b.handle(w, r)
	if w.Code != 401 || b.pairs[key] != nil {
		t.Fatal("revoked native authorized browser")
	}
	p = pair()
	p.Polls = 100
	w = httptest.NewRecorder()
	r.Body = io.NopCloser(strings.NewReader("{}"))
	b.handle(w, r)
	if w.Code != 429 || b.pairs[key] != nil {
		t.Fatal("poll bound")
	}
	p = pair()
	clock = p.Expires
	w = httptest.NewRecorder()
	r.Body = io.NopCloser(strings.NewReader("{}"))
	b.handle(w, r)
	if w.Code != 404 {
		t.Fatal("poll expiry")
	}
	clock = clock.Add(time.Minute)
	for i := 0; i < 5; i++ {
		r.URL.Path = "/v1/web/pairing/start"
		r.Body = io.NopCloser(strings.NewReader("{}"))
		w = httptest.NewRecorder()
		b.handle(w, r)
		if w.Code != 200 {
			t.Fatalf("creation %d", w.Code)
		}
	}
	r.Body = io.NopCloser(strings.NewReader("{}"))
	w = httptest.NewRecorder()
	b.handle(w, r)
	if w.Code != 429 {
		t.Fatal("creation rate")
	}
}
