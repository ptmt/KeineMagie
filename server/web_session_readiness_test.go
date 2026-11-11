package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestWebSessionDoesNotWaitForProvider(t *testing.T) {
	for _, blocked := range []bool{false, true} {
		t.Run(map[bool]string{false: "unavailable", true: "blocked"}[blocked], func(t *testing.T) {
			key := t.TempDir() + "/key"
			if err := os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600); err != nil {
				t.Fatal(err)
			}
			t.Setenv("PROVIDER_KEY_FILE", key)
			var calls atomic.Int32
			release := make(chan struct{})
			defer close(release)
			cfg := &serverConfig{authPath: t.TempDir() + "/auth.json", historyPath: t.TempDir() + "/history.json", httpClient: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
				calls.Add(1)
				if blocked {
					select {
					case <-release:
					case <-r.Context().Done():
						return nil, r.Context().Err()
					}
				}
				return &http.Response{StatusCode: 503, Body: io.NopCloser(strings.NewReader("{}")), Header: http.Header{}}, nil
			})}}
			h, err := newHandler(cfg)
			if err != nil {
				t.Fatal(err)
			}
			native, owner, err := cfg.auth.store.create("fixture", time.Now())
			if err != nil {
				t.Fatal(err)
			}
			token, err := cfg.auth.store.createBrowser(native, owner.UserID, time.Now())
			if err != nil {
				t.Fatal(err)
			}
			if err = cfg.provider.save(owner.UserID, providerCredential{AccessToken: "synthetic", Expires: time.Now().Add(time.Hour), ConnectionID: "synthetic"}); err != nil {
				t.Fatal(err)
			}
			r := httptest.NewRequest("GET", "/v1/web/session", nil)
			r.AddCookie(&http.Cookie{Name: browserCookie, Value: token})
			w := httptest.NewRecorder()
			done := make(chan struct{})
			go func() { h.ServeHTTP(w, r); close(done) }()
			select {
			case <-done:
			case <-time.After(300 * time.Millisecond):
				t.Fatal("identity blocked on provider readiness")
			}
			var body map[string]any
			if err = json.Unmarshal(w.Body.Bytes(), &body); err != nil {
				t.Fatal(err)
			}
			if w.Code != 200 || body["csrf_token"] != browserCSRF(token) || body["expires_at"] == nil || body["user"].(map[string]any)["id"] != owner.UserID {
				t.Fatal("local identity missing")
			}
			if calls.Load() != 0 || body["provider"] != nil || len(body) != 3 {
				t.Fatalf("identity discovered provider: calls=%d", calls.Load())
			}
		})
	}
}
