package main

import (
	"net/http"
	"os"
	"testing"
	"time"
)

// Explicit opt-in local harness: synthetic native identity, no Apple/ChatGPT consent.
func TestLocalBrowserHarness(t *testing.T) {
	dir := os.Getenv("KM_BROWSER_TEST_DIR")
	if dir == "" {
		t.Skip("opt-in local browser harness")
	}
	t.Setenv("WEB_ORIGIN", "http://localhost:8897")
	t.Setenv("AUTH_PATH", dir+"/auth.json")
	t.Setenv("HISTORY_PATH", dir+"/history.json")
	cfg, _ := loadConfig()
	h, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	token, _, e := cfg.auth.store.create("explicit-test-only-native-identity", time.Now())
	if e != nil {
		t.Fatal(e)
	}
	if e = os.WriteFile(dir+"/native-session", []byte(token), 0600); e != nil {
		t.Fatal(e)
	}
	t.Log("LOCAL TEST IDENTITY ONLY: localhost:8897")
	s := &http.Server{Addr: "127.0.0.1:8897", Handler: h, ReadHeaderTimeout: 5 * time.Second}
	timer := time.AfterFunc(8*time.Minute, func() { _ = s.Close() })
	defer timer.Stop()
	if e = s.ListenAndServe(); e != nil && e != http.ErrServerClosed {
		t.Fatal(e)
	}
}
