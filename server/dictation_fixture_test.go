package main

import (
	"encoding/json"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

// Opt-in local integration fixture only. Uses real handler/stores/TTS; no provider credentials.
func TestDictationLocalFixture(t *testing.T) {
	root := os.Getenv("DICTATION_FIXTURE_DIR")
	if root == "" {
		t.Skip("explicit local fixture only")
	}
	cfg := &serverConfig{authPath: filepath.Join(root, "auth.json"), historyPath: filepath.Join(root, "history.json")}
	h, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	token, s, e := cfg.auth.store.create("dictation-local-fixture", time.Now())
	if e != nil {
		t.Fatal(e)
	}
	browser, e := cfg.auth.store.createBrowser(token, s.UserID, time.Now())
	if e != nil {
		t.Fatal(e)
	}
	listener, e := net.Listen("tcp", "127.0.0.1:8799")
	if e != nil {
		t.Fatal(e)
	}
	info, _ := json.Marshal(map[string]string{"native": token, "browser": browser, "csrf": browserCSRF(browser), "url": "http://localhost:8799"})
	if e = os.WriteFile(filepath.Join(root, "fixture.json"), info, 0600); e != nil {
		t.Fatal(e)
	}
	// Explicit test-only cached real-WAV transport; never invokes a provider or
	// creates another spending ledger. Only the already accepted exact source
	// may use these bytes. Authentication and all HTTP mutations remain real.
	if wavPath := os.Getenv("DICTATION_FIXTURE_CACHED_WAV"); wavPath != "" {
		audio, err := os.ReadFile(wavPath)
		if err != nil {
			t.Fatal(err)
		}
		original := h
		h = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			cookie, _ := r.Cookie("__Host-km-session")
			fixtureAuthorized := bearerSession(r) == token || (cookie != nil && cookie.Value == browser)
			if r.Method == "POST" && strings.Contains(r.URL.Path, "/audio/") && fixtureAuthorized {
				parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/v1/learning/dictations/"), "/")
				if len(parts) == 3 {
					index, err := strconv.Atoi(parts[2])
					if err == nil {
						_ = cfg.dictationTransaction(s.UserID, false, func(d *dictationData) error {
							v := dictationFind(d, parts[0])
							if v == nil {
								return errDictationMissing
							}
							for _, segment := range v.Plan {
								if segment.Asset == index && segment.Text == "Heute scheint die Sonne." {
									path := dictationAssetPath(cfg.dictationRoot(s.UserID), v.ID, index)
									if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
										return err
									}
									return os.WriteFile(path, audio, 0600)
								}
							}
							return errDictationMissing
						})
					}
				}
			}
			original.ServeHTTP(w, r)
		})
		t.Log("fixture-only cached WAV injection enabled; no paid transport")
	}
	server := &http.Server{Handler: h, ReadHeaderTimeout: 5 * time.Second}
	defer server.Close()
	done := make(chan error, 1)
	go func() { done <- server.Serve(listener) }()
	t.Log("local fixture ready on loopback 8799; no production stores")
	select {
	case e := <-done:
		t.Fatal(e)
	case <-time.After(20 * time.Minute):
	}
}
