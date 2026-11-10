package main

import (
	"encoding/json"
	"io"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"
)

func TestProviderCatalogFailurePreservesConnectedCredential(t *testing.T) {
	for _, status := range []int{401, 403, 500} {
		t.Run(http.StatusText(status), func(t *testing.T) {
			t.Setenv("PROVIDER_KEY_FILE", t.TempDir()+"/key")
			if err := os.WriteFile(os.Getenv("PROVIDER_KEY_FILE"), []byte(strings.Repeat("k", 32)), 0600); err != nil {
				t.Fatal(err)
			}
			cfg := &serverConfig{authPath: t.TempDir() + "/auth.json", historyPath: t.TempDir() + "/history.json", httpClient: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
				if r.Method != "GET" || !strings.Contains(r.URL.Path, "models") {
					t.Fatal("unexpected provider operation")
				}
				return &http.Response{StatusCode: status, Body: io.NopCloser(strings.NewReader(`{"error":"synthetic-private-body"}`)), Header: http.Header{}}, nil
			})}}
			h, err := newHandler(cfg)
			if err != nil {
				t.Fatal(err)
			}
			token, s, err := cfg.auth.store.create("synthetic", time.Now())
			if err != nil {
				t.Fatal(err)
			}
			if err = cfg.provider.save(s.UserID, providerCredential{AccessToken: "synthetic", Expires: time.Now().Add(time.Hour), ConnectionID: "synthetic"}); err != nil {
				t.Fatal(err)
			}
			w := authCall(h, "GET", "/v1/provider", "", token)
			var result struct {
				Connected bool   `json:"connected"`
				Status    string `json:"status"`
				Selected  string `json:"selected_model"`
			}
			if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &result) != nil || !result.Connected || result.Status != "catalog_unavailable" || result.Selected != "" {
				t.Fatalf("lost persisted connection on catalog failure: HTTP %d", w.Code)
			}
			if strings.Contains(w.Body.String(), "synthetic-private-body") {
				t.Fatal("leaked upstream body")
			}
		})
	}
}
