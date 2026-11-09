package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestPairingSecurityBoundaries(t *testing.T) {
	t.Setenv("WEB_ORIGIN", "https://example.com")
	cfg := &serverConfig{authPath: t.TempDir() + "/auth.json", historyPath: t.TempDir() + "/history.json"}
	h, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	clock := time.Now()
	cfg.auth.now = func() time.Time { return clock }
	a, _, _ := cfg.auth.store.create("alice", clock)
	other, _, _ := cfg.auth.store.create("bob", clock)
	call := func(method, path, body, token, origin, csrf string, cookies ...*http.Cookie) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, path, strings.NewReader(body))
		if token != "" {
			r.Header.Set("Authorization", "Bearer "+token)
		}
		r.Header.Set("Origin", origin)
		r.Header.Set("X-CSRF-Token", csrf)
		for _, c := range cookies {
			r.AddCookie(c)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	boot := call("GET", "/v1/web/config", "", "", "", "")
	var conf map[string]any
	json.Unmarshal(boot.Body.Bytes(), &conf)
	csrf := conf["csrf_token"].(string)
	cookie := boot.Result().Cookies()[0]
	for _, origin := range []string{"", "https://evil.example", "null"} {
		if w := call("POST", "/v1/web/pairing/start", "{}", "", origin, csrf, cookie); w.Code != 403 {
			t.Fatalf("origin %q: %d", origin, w.Code)
		}
	}
	if w := call("POST", "/v1/web/pairing/start", "{}", "", "https://example.com", "bad", cookie); w.Code != 403 {
		t.Fatal("csrf accepted")
	}
	start := func() string {
		w := call("POST", "/v1/web/pairing/start", "{}", "", "https://example.com", csrf, cookie)
		var p map[string]any
		json.Unmarshal(w.Body.Bytes(), &p)
		if w.Code != 200 {
			t.Fatalf("start %d %s", w.Code, w.Body.String())
		}
		return p["user_code"].(string)
	}
	code := start()
	body := `{"user_code":"` + code + `"}`
	if w := call("POST", "/v1/auth/browser/inspect", body, "", "", "", cookie); w.Code != 401 {
		t.Fatal("browser alone inspected")
	}
	w := call("POST", "/v1/auth/browser/inspect", body, a, "", "")
	var preview map[string]any
	json.Unmarshal(w.Body.Bytes(), &preview)
	approval := `{"approval_token":"` + preview["approval_token"].(string) + `","approve":true}`
	if w := call("POST", "/v1/auth/browser/approve", approval, other, "", ""); w.Code != 404 {
		t.Fatal("cross-owner approval")
	}
	if w := call("POST", "/v1/web/pairing/poll", "{}", "", "https://example.com", browserCSRF(randomAuthToken()), &http.Cookie{Name: pairingCookie, Value: randomAuthToken()}); w.Code != 403 {
		t.Fatal("wrong secret accepted")
	}
	if w := call("POST", "/v1/auth/browser/approve", approval, a, "", ""); w.Code != 204 {
		t.Fatal("approval failed")
	}
	if w := call("POST", "/v1/auth/browser/approve", approval, a, "", ""); w.Code != 404 {
		t.Fatal("approval replay")
	}
	// Wrong browser with its own valid bootstrap is not bound to this approval.
	wrong := randomAuthToken()
	if w := call("POST", "/v1/web/pairing/poll", "{}", "", "https://example.com", browserCSRF(wrong), &http.Cookie{Name: pairingCookie, Value: wrong}); w.Code != 404 {
		t.Fatal("poll binding")
	}
	var mu sync.Mutex
	success := 0
	var sessionCookie *http.Cookie
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			w := call("POST", "/v1/web/pairing/poll", "{}", "", "https://example.com", csrf, cookie)
			if w.Code == 200 {
				mu.Lock()
				success++
				sessionCookie = w.Result().Cookies()[0]
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	if success != 1 {
		t.Fatalf("atomic consumption %d", success)
	}
	sc := browserCSRF(sessionCookie.Value)
	for _, path := range []string{"/v1/translations", "/v1/provider/connect", "/v1/provider/disconnect", "/v1/web/logout"} {
		if w := call("POST", path, "{}", "", "https://evil.example", sc, sessionCookie); w.Code != 403 {
			t.Fatalf("origin on %s: %d", path, w.Code)
		}
		if w := call("POST", path, "{}", "", "https://example.com", "bad", sessionCookie); w.Code != 403 {
			t.Fatalf("csrf on %s %d", path, w.Code)
		}
	}
	if w := call("POST", "/v1/auth/browser/inspect", body, sessionCookie.Value, "", ""); w.Code != 401 {
		t.Fatal("browser approved as native")
	}
	if w := call("GET", "/v1/translations", "", "", "", "", sessionCookie); w.Code != 200 || !strings.Contains(w.Body.String(), `"items":[]`) {
		t.Fatalf("browser history %d %s", w.Code, w.Body.String())
	}
	if w := call("POST", "/v1/web/logout", "", "", "https://example.com", sc, sessionCookie); w.Code != 204 || w.Result().Cookies()[0].MaxAge != -1 {
		t.Fatal("logout did not clear")
	}
	if w := call("GET", "/v1/web/session", "", "", "", "", sessionCookie); w.Code != 401 {
		t.Fatal("logout not revoked")
	}
	if _, e := cfg.auth.store.lookup(a, clock); e != nil {
		t.Fatal("native was revoked")
	}
	code = start()
	clock = clock.Add(5 * time.Minute)
	if w := call("POST", "/v1/auth/browser/inspect", `{"user_code":"`+code+`"}`, a, "", ""); w.Code != 404 {
		t.Fatal("expired pairing")
	}
	// Failed guesses are bounded without revealing account identities.
	for i := 0; i < 10; i++ {
		call("POST", "/v1/auth/browser/inspect", `{"user_code":"ZZZZ-ZZZZ"}`, a, "", "")
	}
	if w := call("POST", "/v1/auth/browser/inspect", `{"user_code":"ZZZZ-ZZZZ"}`, a, "", ""); w.Code != 429 {
		t.Fatal("guess limit")
	}
	clock = clock.Add(time.Minute)
	start()
	if w := call("POST", "/v1/web/pairing/poll", "{}", "", "https://example.com", csrf, cookie); w.Code != 202 {
		t.Fatal("pending")
	}
	if w := call("POST", "/v1/web/pairing/poll", "{}", "", "https://example.com", csrf, cookie); w.Code != 429 {
		t.Fatal("poll interval")
	}
}
