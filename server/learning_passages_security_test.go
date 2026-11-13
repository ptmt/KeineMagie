package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestPassageBrowserMutationRequiresOriginAndCSRF(t *testing.T) {
	t.Setenv("WEB_ORIGIN", "https://example.com")
	cfg, h, token, _, j := learningFixture(t)
	s, _ := cfg.auth.store.lookup(token, time.Now())
	browser, e := cfg.auth.store.createBrowser(token, s.UserID, time.Now())
	if e != nil {
		t.Fatal(e)
	}
	for _, tc := range []struct {
		origin, csrf string
		want         int
	}{{"", browserCSRF(browser), 403}, {"https://example.com", "", 403}, {"https://evil.example", browserCSRF(browser), 403}, {"https://example.com", browserCSRF(browser), 200}} {
		r := httptest.NewRequest("PUT", "/v1/learning/episodes/"+j.ID+"/passages/0", strings.NewReader(`{"favorite":true}`))
		r.AddCookie(&http.Cookie{Name: browserCookie, Value: browser})
		r.Header.Set("Origin", tc.origin)
		r.Header.Set("X-CSRF-Token", tc.csrf)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != tc.want {
			t.Fatalf("CSRF status=%d want=%d", w.Code, tc.want)
		}
	}
}
