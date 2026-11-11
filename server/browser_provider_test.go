package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

func TestBrowserProviderBootstrapUsesCookieOwnerAndCSRF(t *testing.T) {
	t.Setenv("WEB_ORIGIN", "https://example.com")
	key := t.TempDir() + "/key"
	os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600)
	t.Setenv("PROVIDER_KEY_FILE", key)
	cfg := &serverConfig{authPath: t.TempDir() + "/auth.json", historyPath: t.TempDir() + "/history.json"}
	h, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	native, owner, _ := cfg.auth.store.create("owner", time.Now())
	browser, e := cfg.auth.store.createBrowser(native, owner.UserID, time.Now())
	if e != nil {
		t.Fatal(e)
	}
	call := func(method, path, csrf string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, path, strings.NewReader("{}"))
		r.AddCookie(&http.Cookie{Name: browserCookie, Value: browser})
		r.Header.Set("Origin", "https://example.com")
		r.Header.Set("X-CSRF-Token", csrf)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	w := call("GET", "/v1/web/session", "")
	if w.Code != 200 || strings.Contains(w.Body.String(), `"provider"`) || !strings.Contains(w.Body.String(), `"csrf_token"`) {
		t.Fatalf("local session %d %s", w.Code, w.Body.String())
	}
	if w = call("GET", "/v1/provider", ""); w.Code != 200 || !strings.Contains(w.Body.String(), `"status":"not_connected"`) {
		t.Fatalf("independent provider %d %s", w.Code, w.Body.String())
	}
	if w = call("POST", "/v1/provider/connect", ""); w.Code != 403 {
		t.Fatal("bootstrap no csrf")
	}
	w = call("POST", "/v1/provider/connect", browserCSRF(browser))
	if w.Code != 200 {
		t.Fatalf("bootstrap %d %s", w.Code, w.Body.String())
	}
	var out map[string]any
	json.Unmarshal(w.Body.Bytes(), &out)
	code := out["bootstrap_token"].(string)
	attempt := cfg.provider.attempts[sessionHash(code)]
	if attempt.User != owner.UserID || attempt.Session != browser {
		t.Fatal("bootstrap owner/session mismatch")
	}
	// No provider access or refresh token is part of the browser bootstrap response.
	if strings.Contains(w.Body.String(), "access_token") || strings.Contains(w.Body.String(), "refresh_token") {
		t.Fatal("provider secret exposed")
	}
	if w = call("POST", "/v1/web/logout", browserCSRF(browser)); w.Code != 204 {
		t.Fatal("logout")
	}
	r := httptest.NewRequest("POST", "/v1/provider/bootstrap/start", strings.NewReader(`{"bootstrap_token":"`+code+`","redirect_uri":"http://127.0.0.1:53001/auth/callback"}`))
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 401 {
		t.Fatalf("bootstrap survived logout %d", w.Code)
	}
}
