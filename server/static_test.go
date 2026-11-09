package main

import (
	"net/http/httptest"
	"strings"
	"testing"
)

func TestPublicWebAssetsOnly(t *testing.T) {
	h := authHandler(t)
	for _, path := range []string{"/", "/app.mjs", "/core.mjs", "/styles.css", "/favicon.svg"} {
		r := httptest.NewRequest("GET", path, nil)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != 200 {
			t.Fatalf("%s: %d", path, w.Code)
		}
		if !strings.Contains(w.Header().Get("Content-Security-Policy"), "frame-ancestors 'none'") {
			t.Fatal("missing CSP")
		}
	}
	for _, path := range []string{"/.env", "/tests/core.test.mjs", "/server/auth.go", "/data/auth.json", "/../server/.env"} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code == 200 {
			t.Fatalf("source exposed %s", path)
		}
	}
}
