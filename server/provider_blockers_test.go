package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Signal exactly when a handler starts reading an incomplete request body.
type signalingProviderBody struct {
	io.ReadCloser
	entered chan struct{}
}

func (b *signalingProviderBody) Read(p []byte) (int, error) {
	select {
	case <-b.entered:
	default:
		close(b.entered)
	}
	return b.ReadCloser.Read(p)
}

func TestHTTPServerSlowBodyTimeout(t *testing.T) {
	if os.Getenv("KM_BODY_TIMEOUT_CHILD") == "1" {
		main()
		return
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := fmt.Sprint(listener.Addr().(*net.TCPAddr).Port)
	listener.Close()
	dir := t.TempDir()
	cmd := exec.Command(os.Args[0], "-test.run=^TestHTTPServerSlowBodyTimeout$")
	cmd.Env = append(os.Environ(), "KM_BODY_TIMEOUT_CHILD=1", "HOST=127.0.0.1", "PORT="+port, "AUTH_PATH="+filepath.Join(dir, "auth.json"), "HISTORY_PATH="+filepath.Join(dir, "history.json"), "PROVIDER_KEY_FILE=")
	if err = cmd.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { cmd.Process.Kill(); cmd.Wait() }()
	var conn net.Conn
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		conn, err = net.DialTimeout("tcp", "127.0.0.1:"+port, 100*time.Millisecond)
		if err == nil {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	// This public handler parses JSON before checking its bootstrap token.
	fmt.Fprint(conn, "POST /v1/provider/bootstrap/start HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: 100\r\nConnection: close\r\n\r\n{")
	conn.SetReadDeadline(time.Now().Add(12 * time.Second))
	resp, err := http.ReadResponse(bufio.NewReader(conn), nil)
	if err != nil {
		t.Fatalf("server did not reject withheld body within 12s: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 400 && resp.StatusCode != 408 {
		t.Fatalf("body timeout status %d", resp.StatusCode)
	}
}

func TestProviderDisconnectWithoutKeyCannotReconnect(t *testing.T) {
	key := filepath.Join(t.TempDir(), "key")
	keyBytes := []byte(strings.Repeat("k", 32))
	if err := os.WriteFile(key, keyBytes, 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PROVIDER_KEY_FILE", key)
	cfg := &serverConfig{authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json")}
	if _, err := newHandler(cfg); err != nil {
		t.Fatal(err)
	}
	token, session, err := cfg.auth.store.create("owner", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if err = cfg.provider.save(session.UserID, providerCredential{ClientID: "oaiapp_test", AccessToken: "synthetic-access", RefreshToken: "synthetic-refresh", Expires: time.Now().Add(time.Hour)}); err != nil {
		t.Fatal(err)
	}
	if err = os.Remove(key); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PROVIDER_KEY_FILE", "")
	disabled := &serverConfig{authPath: cfg.authPath, historyPath: cfg.historyPath}
	h, err := newHandler(disabled)
	if err != nil {
		t.Fatal(err)
	}
	w := authCall(h, "POST", "/v1/provider/disconnect", "{}", token)
	if w.Code < 200 || w.Code >= 300 {
		t.Fatalf("local disconnect failed %d %s", w.Code, w.Body.String())
	}
	if err = os.WriteFile(key, keyBytes, 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PROVIDER_KEY_FILE", key)
	restored := &serverConfig{authPath: cfg.authPath, historyPath: cfg.historyPath}
	h, err = newHandler(restored)
	if err != nil {
		t.Fatal(err)
	}
	c, err := restored.provider.load(session.UserID)
	if err == nil && (c.AccessToken != "" || c.RefreshToken != "") {
		t.Fatal("successful disconnect left renewable credentials after key restoration")
	}
	if err != nil && !os.IsNotExist(err) {
		t.Fatal(err)
	}
	status := authCall(h, "GET", "/v1/provider", "", token)
	if status.Code != 200 || !strings.Contains(status.Body.String(), `"connected":false`) {
		t.Fatalf("restored status %d %s", status.Code, status.Body.String())
	}
	var result struct {
		Revoked   *bool `json:"revoked"`
		Connected *bool `json:"connected"`
	}
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &result) != nil || result.Revoked == nil || *result.Revoked || result.Connected == nil || *result.Connected {
		t.Fatalf("revocation must be explicitly unconfirmed: %d %s", w.Code, w.Body.String())
	}
}

func TestProviderOwnerLockCancellationAndCleanup(t *testing.T) {
	p := &providerService{}
	release, err := p.lockOwner(context.Background(), "alice")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	done := make(chan error, 1)
	go func() {
		unlock, err := p.lockOwner(ctx, "alice")
		if unlock != nil {
			unlock()
		}
		done <- err
	}()
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("cancellation: %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("canceled waiter blocked")
	}
	bob, err := p.lockOwner(context.Background(), "bob")
	if err != nil {
		t.Fatal(err)
	}
	bob()
	release()
	if len(p.owners) != 0 {
		t.Fatal("idle owner locks retained")
	}
	release, err = p.lockOwner(context.Background(), "alice")
	if err != nil {
		t.Fatal(err)
	}
	release()
}

func TestProviderSlowUpstreamDoesNotBlockOtherOwner(t *testing.T) {
	t.Setenv("PROVIDER_KEY_FILE", filepath.Join(t.TempDir(), "key"))
	if err := os.WriteFile(os.Getenv("PROVIDER_KEY_FILE"), []byte(strings.Repeat("k", 32)), 0600); err != nil {
		t.Fatal(err)
	}
	entered, unblock := make(chan struct{}), make(chan struct{})
	cfg := &serverConfig{authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json"), httpClient: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		close(entered)
		<-unblock
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(`{"models":[{"slug":"offered","visibility":"list"}]}`))}, nil
	})}}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	alice, session, err := cfg.auth.store.create("alice", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	bob, _, err := cfg.auth.store.create("bob", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if err = cfg.provider.save(session.UserID, providerCredential{AccessToken: "synthetic", Expires: time.Now().Add(time.Hour)}); err != nil {
		t.Fatal(err)
	}
	finished := make(chan struct{})
	go func() { defer close(finished); authCall(h, "GET", "/v1/provider", "", alice) }()
	defer func() { close(unblock); <-finished }()
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("no upstream request")
	}
	done := make(chan int, 1)
	go func() { done <- authCall(h, "GET", "/v1/provider", "", bob).Code }()
	select {
	case code := <-done:
		if code != 200 {
			t.Fatalf("Bob status %d", code)
		}
	case <-time.After(300 * time.Millisecond):
		t.Fatal("Alice's upstream request blocked Bob")
	}
}

func TestProviderSlowBodyDoesNotBlockOtherOwner(t *testing.T) {
	for _, path := range []string{"/v1/provider/connect", "/v1/translations"} {
		t.Run(path, func(t *testing.T) {
			t.Setenv("PROVIDER_KEY_FILE", "")
			cfg := &serverConfig{authPath: t.TempDir() + "/auth.json", historyPath: t.TempDir() + "/history.json"}
			h, err := newHandler(cfg)
			if err != nil {
				t.Fatal(err)
			}
			alice, _, err := cfg.auth.store.create("alice", time.Now())
			if err != nil {
				t.Fatal(err)
			}
			bob, _, err := cfg.auth.store.create("bob", time.Now())
			if err != nil {
				t.Fatal(err)
			}
			reader, writer := io.Pipe()
			entered, finished := make(chan struct{}), make(chan struct{})
			req := httptest.NewRequest(http.MethodPost, path, nil)
			req.Body = &signalingProviderBody{ReadCloser: reader, entered: entered}
			req.Header.Set("Authorization", "Bearer "+alice)
			go func() { defer close(finished); h.ServeHTTP(httptest.NewRecorder(), req) }()
			defer func() { writer.Close(); reader.Close(); <-finished }()
			select {
			case <-entered:
			case <-time.After(time.Second):
				t.Fatal("handler never read body")
			}
			done := make(chan int, 1)
			go func() { done <- authCall(h, "GET", "/v1/provider", "", bob).Code }()
			select {
			case code := <-done:
				if code != http.StatusOK {
					t.Fatalf("Bob status: %d", code)
				}
			case <-time.After(300 * time.Millisecond):
				t.Fatal("Alice's withheld body blocked Bob's provider status")
			}
		})
	}
}
