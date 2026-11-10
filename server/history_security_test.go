package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestHistoryBrowserMutationsRequireCookieOriginAndCSRF(t *testing.T) {
	t.Setenv("WEB_ORIGIN", "https://example.com")
	cfg, h, native, _, _ := historyFixture(t)
	s, err := cfg.auth.store.lookup(native, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	browser, err := cfg.auth.store.createBrowser(native, s.UserID, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	for _, method := range []string{"PATCH", "DELETE"} {
		for _, tc := range []struct {
			name, origin, csrf, bearer string
			cookie                     bool
			status                     int
		}{
			{"missing CSRF", "https://example.com", "", "", true, 403},
			{"wrong CSRF", "https://example.com", "wrong", "", true, 403},
			{"wrong origin", "https://evil.invalid", browserCSRF(browser), "", true, 403},
			{"missing origin", "", browserCSRF(browser), "", true, 403},
			{"no cookie", "https://example.com", browserCSRF(browser), native, false, 401},
			{"browser bearer bypass", "", "", browser, false, 401},
			{"native bearer in browser", "https://evil.invalid", "", native, false, 401},
			{"valid", "https://example.com", browserCSRF(browser), "", true, map[string]int{"PATCH": 200, "DELETE": 204}[method]},
		} {
			t.Run(method+tc.name, func(t *testing.T) {
				r := httptest.NewRequest(method, "/v1/history/test-record", strings.NewReader(`{"favorite":true}`))
				if tc.cookie {
					r.AddCookie(&http.Cookie{Name: browserCookie, Value: browser})
				}
				if tc.bearer != "" {
					r.Header.Set("Authorization", "Bearer "+tc.bearer)
				}
				r.Header.Set("Origin", tc.origin)
				r.Header.Set("X-CSRF-Token", tc.csrf)
				w := httptest.NewRecorder()
				h.ServeHTTP(w, r)
				if w.Code != tc.status {
					t.Fatalf("got %d want %d: %s", w.Code, tc.status, w.Body.String())
				}
			})
		}
	}
}

func TestHistoryRejectsInvalidPatchAndHidesForeignRecords(t *testing.T) {
	cfg, h, token, _, _ := historyFixture(t)
	foreign, _, err := cfg.auth.store.create("other-owner", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	for _, method := range []string{"PATCH", "DELETE"} {
		for _, id := range []string{"test-record", "unknown"} {
			w := authCall(h, method, "/v1/history/"+id, `{"favorite":true}`, foreign)
			if w.Code != 404 || strings.TrimSpace(w.Body.String()) != `{"error":"history record not found"}` {
				t.Fatalf("foreign %s %s: %d %s", method, id, w.Code, w.Body.String())
			}
		}
		for _, bearer := range []string{"", "invalid"} {
			w := authCall(h, method, "/v1/history/test-record", `{"favorite":true}`, bearer)
			if w.Code != 401 {
				t.Fatalf("unauthorized %s: %d", method, w.Code)
			}
		}
	}
	for _, body := range []string{`{}`, `null`, `[]`, `{"favorite":null}`, `{"favorite":"true"}`, `{"favorite":1}`, `{"favorite":true,"owner":"other"}`, `{"favorite":true} {}`, `{"favorite":true`, strings.Repeat(" ", 1025) + `{"favorite":true}`} {
		w := authCall(h, "PATCH", "/v1/history/test-record", body, token)
		if w.Code != 400 {
			t.Errorf("invalid %q: %d", body, w.Code)
		}
	}
	for _, method := range []string{"GET", "POST", "PUT"} {
		w := authCall(h, method, "/v1/history/test-record", `{}`, token)
		if w.Code != 405 {
			t.Errorf("method %s: %d", method, w.Code)
		}
	}
	w := authCall(h, "GET", "/v1/translations", "", token)
	if strings.Contains(w.Body.String(), `"favorite":true`) {
		t.Fatal("invalid or foreign mutation changed record")
	}
}
