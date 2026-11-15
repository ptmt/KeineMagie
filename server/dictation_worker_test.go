package main

import (
	"bytes"
	"context"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDictationPrivateWorkerReconnectAfterDeath(t *testing.T) {
	dir, err := os.MkdirTemp(os.Getenv("DICTATION_TEST_SCRATCH"), "dwr-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	socket := filepath.Join(dir, "worker.sock")
	t.Setenv("DICTATION_TTS_SOCKET", socket)
	t.Setenv("DICTATION_TTS_EXECUTABLE", "")
	listener, err := net.Listen("unix", socket)
	if err != nil {
		t.Fatal(err)
	}
	accepted := make(chan struct{})
	go func() {
		conn, e := listener.Accept()
		if e == nil {
			close(accepted)
			conn.Close() // Simulate SIGKILL before a response.
		}
	}()
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if _, err := dictationLegacySynthesize(ctx, "Hallo."); err == nil {
		t.Fatal("dead worker returned success")
	}
	select {
	case <-accepted:
	case <-time.After(time.Second):
		t.Fatal("worker never accepted request")
	}
	listener.Close()
	if err := os.Remove(socket); err != nil && !os.IsNotExist(err) {
		t.Fatal(err)
	}
	listener, err = net.Listen("unix", socket)
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	server := http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "audio/wav")
		w.Write(append([]byte("RIFF0000WAVE"), make([]byte, 40)...))
	})}
	go server.Serve(listener)
	defer server.Close()
	b, err := dictationLegacySynthesize(context.Background(), "Hallo.")
	if err != nil || len(b) != 52 {
		t.Fatalf("restarted worker: %d bytes, %v", len(b), err)
	}
}

func TestDictationPrivateWorkerTransport(t *testing.T) {
	dir, err := os.MkdirTemp(os.Getenv("DICTATION_TEST_SCRATCH"), "dw-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	socket := filepath.Join(dir, "t.sock")
	listener, err := net.Listen("unix", socket)
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	server := http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/synthesize" || r.Method != "POST" {
			t.Error("unexpected operation")
		}
		if r.Header.Get("Authorization") != "" || r.Header.Get("Cookie") != "" {
			t.Error("credentials forwarded")
		}
		// Transport-only fixture, not speech evidence.
		w.Header().Set("Content-Type", "audio/wav")
		w.Write(append([]byte("RIFF0000WAVE"), make([]byte, 40)...))
	})}
	go server.Serve(listener)
	defer server.Close()
	t.Setenv("DICTATION_TTS_SOCKET", socket)
	t.Setenv("DICTATION_TTS_EXECUTABLE", "")
	if !dictationLegacyTTSAvailable() {
		t.Fatal("private worker unavailable")
	}
	b, err := dictationLegacySynthesize(context.Background(), "Hallo.")
	if err != nil || len(b) != 52 {
		t.Fatalf("worker response %d %v", len(b), err)
	}
}
func TestDictationPrivateWorkerCancellation(t *testing.T) {
	dir, err := os.MkdirTemp(os.Getenv("DICTATION_TEST_SCRATCH"), "dw-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	socket := filepath.Join(dir, "t.sock")
	listener, err := net.Listen("unix", socket)
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	canceled := make(chan struct{})
	server := http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		io.Copy(io.Discard, r.Body)
		<-r.Context().Done()
		close(canceled)
	})}
	go server.Serve(listener)
	defer server.Close()
	t.Setenv("DICTATION_TTS_SOCKET", socket)
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	if _, err := dictationLegacySynthesize(ctx, "Hallo."); err == nil {
		t.Fatal("canceled request succeeded")
	}
	select {
	case <-canceled:
	case <-time.After(time.Second):
		t.Fatal("worker request not canceled")
	}
}
func TestDictationRealPrivateWorker(t *testing.T) {
	if os.Getenv("DICTATION_REAL_WORKER_TEST") != "1" {
		t.Skip("explicit real Linux worker only")
	}
	b, err := dictationLegacySynthesize(context.Background(), "Heute scheint die Sonne. Wir gehen gemeinsam in den Park.")
	if err != nil {
		t.Fatal(err)
	}
	if len(b) < 10000 {
		t.Fatalf("speech unexpectedly short: %d", len(b))
	}
	if err = os.WriteFile("/output/worker-german.wav", b, 0600); err != nil {
		t.Fatal(err)
	}
	t.Logf("real Piper WAV: %d bytes", len(b))
	cfg, call := dictationTestAPI(t)
	if w := call("POST", "", `{"id":"linux","title":"Linux private worker","text":"Heute scheint die Sonne.","language":"de"}`); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	if w := call("POST", "/linux/audio/0", `{}`); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	if w := call("GET", "/linux/audio/0", ""); w.Code != 200 || w.Body.Len() < 10000 {
		t.Fatal("real authenticated asset", w.Code, w.Body.Len())
	}
	ownerToken, _, err := cfg.auth.store.create("lifecycle-owner", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		token  string
		status int
	}{{ownerToken, 206}, {"", 401}} {
		r := httptest.NewRequest("GET", "/v1/learning/dictations/linux/audio/0", nil)
		if tc.token != "" {
			r.Header.Set("Authorization", "Bearer "+tc.token)
		}
		r.Header.Set("Range", "bytes=0-11")
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != tc.status || tc.status == 206 && (w.Body.Len() != 12 || !bytes.Equal(w.Body.Bytes()[:4], []byte("RIFF")) || !bytes.Equal(w.Body.Bytes()[8:], []byte("WAVE"))) {
			t.Fatalf("real authenticated Range: %d %q", w.Code, w.Body.Bytes())
		}
	}
	if w := call("POST", "/linux/audio/0", `{}`); w.Code != 200 {
		t.Fatal("idempotent asset", w.Code)
	}
	if w := call("DELETE", "/linux", `{"revision":0}`); w.Code != 200 {
		t.Fatal("delete", w.Code)
	}
	if w := call("GET", "/linux/audio/0", ""); w.Code != 404 {
		t.Fatal("deleted asset", w.Code)
	}
}

// Host Docker orchestration kills the worker only after observing child.py.
// This test process has no Docker socket and stays alive across the restart.
func TestDictationRealWorkerKillRecovery(t *testing.T) {
	if os.Getenv("DICTATION_REAL_KILL_TEST") != "1" {
		t.Skip("explicit isolated Linux worker SIGKILL test only")
	}
	readyDeadline := time.Now().Add(10 * time.Second)
	for !dictationLegacyTTSAvailable() && time.Now().Before(readyDeadline) {
		time.Sleep(50 * time.Millisecond)
	}
	if !dictationLegacyTTSAvailable() {
		t.Fatal("worker socket did not appear")
	}
	if err := os.WriteFile("/output/backend-started", []byte("1"), 0600); err != nil {
		t.Fatal(err)
	}
	text := strings.Repeat("Heute gehen wir gemeinsam in den Park. ", 30)
	if _, err := dictationLegacySynthesize(context.Background(), text); err == nil {
		t.Fatal("synthesis succeeded after worker SIGKILL")
	}
	if err := os.WriteFile("/output/kill-observed", []byte("1"), 0600); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(20 * time.Second)
	for time.Now().Before(deadline) {
		b, err := dictationLegacySynthesize(context.Background(), "Heute scheint die Sonne.")
		if err == nil {
			if len(b) < 10000 || !bytes.Equal(b[:4], []byte("RIFF")) || !bytes.Equal(b[8:12], []byte("WAVE")) {
				t.Fatalf("invalid recovered speech: %d bytes", len(b))
			}
			if err := os.WriteFile("/output/recovered.wav", b, 0600); err != nil {
				t.Fatal(err)
			}
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatal("worker restart did not restore synthesis")
}

// Host orchestration SIGKILLs this Go process during real synthesis and then
// checks that the worker's engine child exits after the Unix peer disappears.
func TestDictationRealBackendKill(t *testing.T) {
	if os.Getenv("DICTATION_REAL_BACKEND_KILL_TEST") != "1" {
		t.Skip("explicit isolated Linux backend SIGKILL test only")
	}
	readyDeadline := time.Now().Add(10 * time.Second)
	for !dictationLegacyTTSAvailable() && time.Now().Before(readyDeadline) {
		time.Sleep(50 * time.Millisecond)
	}
	if !dictationLegacyTTSAvailable() {
		t.Fatal("worker socket did not appear")
	}
	if err := os.WriteFile("/output/backend-kill-started", []byte("1"), 0600); err != nil {
		t.Fatal(err)
	}
	_, _ = dictationLegacySynthesize(context.Background(), strings.Repeat("Heute gehen wir gemeinsam in den Park. ", 30))
	t.Fatal("backend was not killed during synthesis")
}
