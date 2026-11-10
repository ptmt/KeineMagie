package main

import (
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Opt-in public authorization-page probe. Uses only a disposable local owner,
// fresh host/state/nonce/PKCE, and a live loopback listener; never real tokens.
func TestProviderAuthorizeDiagnostic(t *testing.T) {
	out := os.Getenv("KEINEMAGIE_AUTHORIZE_PROBE")
	if out == "" {
		t.Skip("set KEINEMAGIE_AUTHORIZE_PROBE to a scratch output path")
	}
	key := filepath.Join(t.TempDir(), "key")
	if err := os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PROVIDER_KEY_FILE", key)
	cfg := &serverConfig{authPath: t.TempDir() + "/auth.json", historyPath: t.TempDir() + "/history.json"}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	token, _, err := cfg.auth.store.create("disposable-authorize-diagnostic", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	w := authCall(h, "POST", "/v1/provider/connect", "{}", token)
	if w.Code != 200 {
		t.Fatalf("connect HTTP %d", w.Code)
	}
	var attempt struct {
		Token string `json:"bootstrap_token"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &attempt); err != nil {
		t.Fatal(err)
	}
	body, _ := json.Marshal(map[string]string{"bootstrap_token": attempt.Token, "redirect_uri": "http://" + listener.Addr().String() + "/auth/callback"})
	w = authCall(h, "POST", "/v1/provider/bootstrap/start", string(body), "")
	if w.Code != 200 {
		t.Fatalf("start HTTP %d", w.Code)
	}
	if err := os.WriteFile(out, w.Body.Bytes(), 0600); err != nil {
		t.Fatal(err)
	}
	t.Log("Disposable authorize request saved; no credentials or exchange performed")
	if os.Getenv("KEINEMAGIE_AUTHORIZE_PROBE_WAIT") != "" {
		time.Sleep(180 * time.Second)
	}
}
