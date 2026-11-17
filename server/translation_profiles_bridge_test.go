package main

import (
	"encoding/json"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"sync/atomic"
	"testing"
	"time"
)

// Disposable production-handler bridge; no provider credential is configured.
func TestTranslationProfilesClientBridge(t *testing.T) {
	dir := os.Getenv("KM_PROFILE_BRIDGE_DIR")
	if dir == "" {
		t.Skip("profile client bridge not requested")
	}
	listener, e := net.Listen("tcp", "127.0.0.1:0")
	if e != nil {
		t.Fatal(e)
	}
	origin := "http://localhost:" + strconv.Itoa(listener.Addr().(*net.TCPAddr).Port)
	t.Setenv("WEB_ORIGIN", origin)
	cfg, h, a, b, history := historyFixture(t)
	if e := history.delete("test-record"); e != nil {
		t.Fatal(e)
	}
	s, _ := cfg.auth.store.lookup(a, time.Now())
	browser, e := cfg.auth.store.createBrowser(a, s.UserID, time.Now())
	if e != nil {
		t.Fatal(e)
	}
	var forbidden atomic.Int64
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if (r.URL.Path == "/v1/translations" && r.Method == "POST") || r.URL.Path == "/tts" || r.URL.Path == "/v1/translation-followups" {
			forbidden.Add(1)
			writeError(w, 500, "inference forbidden by fixture")
			return
		}
		h.ServeHTTP(w, r)
	})
	server := &http.Server{Handler: handler, ReadHeaderTimeout: 5 * time.Second}
	defer server.Close()
	go server.Serve(listener)
	data, _ := json.Marshal(map[string]string{"url": origin, "token": a, "second_token": b, "owner": s.UserID, "cookie": browser, "cookie_name": browserCookie, "csrf": browserCSRF(browser)})
	if e = os.WriteFile(filepath.Join(dir, "ready.json"), data, 0600); e != nil {
		t.Fatal(e)
	}
	deadline := time.Now().Add(4 * time.Minute)
	for time.Now().Before(deadline) {
		if _, e := os.Stat(filepath.Join(dir, "stop")); e == nil {
			if forbidden.Load() != 0 {
				t.Fatalf("unexpected inference endpoints: %d", forbidden.Load())
			}
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatal("client bridge did not finish")
}
