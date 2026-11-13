package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestBrowserPairingTracer(t *testing.T) {
	t.Setenv("AUTH_PATH", t.TempDir()+"/auth.json")
	t.Setenv("HISTORY_PATH", t.TempDir()+"/history.json")
	t.Setenv("WEB_ORIGIN", "https://example.com")
	cfg, _ := loadConfig()
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	issued := time.Now().UTC()
	cfg.auth.now = func() time.Time { return issued }
	native, owner, err := cfg.auth.store.create("alice", cfg.auth.now())
	if err != nil {
		t.Fatal(err)
	}
	call := func(path, body, token, csrf string, cookies []*http.Cookie) *httptest.ResponseRecorder {
		r := httptest.NewRequest("POST", "https://example.com"+path, strings.NewReader(body))
		if token == "" {
			r.Header.Set("Origin", "https://example.com")
		}
		r.Header.Set("X-CSRF-Token", csrf)
		if token != "" {
			r.Header.Set("Authorization", "Bearer "+token)
		}
		for _, c := range cookies {
			r.AddCookie(c)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	r := httptest.NewRequest("GET", "https://example.com/v1/web/config", nil)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	var config struct {
		PairingAvailable bool   `json:"pairing_available"`
		CSRF             string `json:"csrf_token"`
	}
	json.Unmarshal(w.Body.Bytes(), &config)
	if !config.PairingAvailable || config.CSRF == "" {
		t.Fatalf("pairing unavailable: %s", w.Body.String())
	}
	cookies := w.Result().Cookies()
	if len(cookies) != 1 || cookies[0].MaxAge != 300 || !cookies[0].Secure || !cookies[0].HttpOnly || cookies[0].SameSite != http.SameSiteStrictMode || cookies[0].Path != "/" || !strings.HasPrefix(cookies[0].Name, "__Host-") {
		t.Fatalf("unsafe cookies: %v", cookies)
	}
	w = call("/v1/web/pairing/start", "{}", "", config.CSRF, cookies)
	if w.Code != 200 {
		t.Fatalf("start %d %s", w.Code, w.Body.String())
	}
	var pair struct {
		Code string `json:"user_code"`
	}
	json.Unmarshal(w.Body.Bytes(), &pair)
	if len(pair.Code) != 9 {
		t.Fatalf("code %q", pair.Code)
	}
	w = call("/v1/auth/browser/inspect", `{"user_code":"`+pair.Code+`"}`, native, "", nil)
	if w.Code != 200 {
		t.Fatalf("inspect %d %s", w.Code, w.Body.String())
	}
	var preview struct {
		Approval string `json:"approval_token"`
	}
	json.Unmarshal(w.Body.Bytes(), &preview)
	if preview.Approval == "" {
		t.Fatal("missing explicit approval")
	}
	w = call("/v1/auth/browser/approve", `{"approval_token":"`+preview.Approval+`","approve":true}`, native, "", nil)
	if w.Code != 204 {
		t.Fatalf("approve %d %s", w.Code, w.Body.String())
	}
	w = call("/v1/web/pairing/poll", "{}", "", config.CSRF, cookies)
	if w.Code != 200 {
		t.Fatalf("poll %d %s", w.Code, w.Body.String())
	}
	sessions := w.Result().Cookies()
	if len(sessions) == 0 {
		t.Fatal("no browser session")
	}
	r = httptest.NewRequest("GET", "https://example.com/v1/web/session", nil)
	for _, c := range sessions {
		if c.MaxAge >= 0 {
			r.AddCookie(c)
		}
	}
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 200 || !strings.Contains(w.Body.String(), owner.UserID) || strings.Contains(w.Body.String(), native) {
		t.Fatalf("session %d %s", w.Code, w.Body.String())
	}
	if w = call("/v1/web/pairing/poll", "{}", "", config.CSRF, cookies); w.Code != 404 {
		t.Fatalf("replay %d", w.Code)
	}
	var sessionCookie *http.Cookie
	for _, c := range sessions {
		if c.Name == browserCookie {
			sessionCookie = c
		}
	}
	assertBrowserLifetime(t, h, cfg, sessionCookie, issued, "https://example.com")
}
