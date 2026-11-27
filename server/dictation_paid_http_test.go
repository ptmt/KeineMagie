package main

import (
	"context"
	"errors"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func dictationPaidTestConfig(t *testing.T) {
	t.Helper()
	t.Setenv("DICTATION_TTS_PROVIDER", "openai-realtime")
	t.Setenv("DICTATION_OPENAI_API_KEY", "synthetic-transport-only")
	t.Setenv("DICTATION_OPENAI_API_KEY_FILE", "")
	for k, v := range map[string]string{"MODEL": "gpt-realtime-2.1-mini", "VOICE": "marin", "MAX_CHARS": "1800", "MAX_SECONDS": "10", "MAX_OUTPUT_TOKENS": "100", "TIMEOUT_SECONDS": "10", "DAILY_CHARS": "100", "DAILY_SECONDS": "20", "DAILY_REQUESTS": "2", "CONCURRENCY": "1"} {
		t.Setenv("DICTATION_OPENAI_"+k, v)
	}
}

func TestDictationPaidCancellationAndBusyAdmission(t *testing.T) {
	dictationPaidTestConfig(t)
	cfg, call := dictationTestAPI(t)
	if w := call("POST", "", `{"id":"cancel","title":"Test","text":"Hallo.","language":"de"}`); w.Code != 200 {
		t.Fatal(w.Code)
	}
	entered, release := make(chan struct{}), make(chan struct{})
	cfg.dictationSpeech = func(ctx context.Context, c dictationOpenAIConfig, text string) ([]byte, error) {
		close(entered)
		<-release
		return append([]byte("RIFF0000WAVE"), make([]byte, 40)...), nil
	}
	token, _, err := cfg.auth.store.create("lifecycle-owner", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	req := httptest.NewRequest("POST", "/v1/learning/dictations/cancel/audio/0", strings.NewReader("{}")).WithContext(ctx)
	req.Header.Set("Authorization", "Bearer "+token)
	done := make(chan struct{})
	w := httptest.NewRecorder()
	go func() { h.ServeHTTP(w, req); close(done) }()
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("generation never started")
	}
	if busy := call("POST", "/cancel/audio/0", "{}"); busy.Code != 429 {
		t.Fatal("parallel admission", busy.Code)
	}
	cancel()
	close(release)
	<-done
	if w.Code == 200 {
		t.Fatal("canceled output published")
	}
	if get := call("GET", "/cancel/audio/0", ""); get.Code != 404 {
		t.Fatal("canceled audio accessible", get.Code)
	}
}

func TestDictationPaidCachedReplayAndUncertainRetry(t *testing.T) {
	dictationPaidTestConfig(t)
	cfg, call := dictationTestAPI(t)
	var calls atomic.Int32
	cfg.dictationSpeech = func(ctx context.Context, c dictationOpenAIConfig, text string) ([]byte, error) {
		calls.Add(1)
		if err := c.beforeAttempt(ctx); err != nil {
			return nil, err
		}
		if text == "Fehler." {
			return nil, errors.New("synthetic lost connection after send")
		}
		return append([]byte("RIFF0000WAVE"), make([]byte, 40)...), nil // synthetic HTTP fixture only
	}
	for _, id := range []string{"cached", "uncertain"} {
		text := "Hallo."
		if id == "uncertain" {
			text = "Fehler."
		}
		if w := call("POST", "", `{"id":"`+id+`","title":"Test","text":"`+text+`","language":"de"}`); w.Code != 200 {
			t.Fatal(w.Code, w.Body.String())
		}
	}
	for i := 0; i < 3; i++ {
		if w := call("POST", "/cached/audio/0", "{}"); w.Code != 200 {
			t.Fatal(w.Code)
		}
	}
	for i := 0; i < 3; i++ {
		if w := call("GET", "/cached/audio/0", ""); w.Code != 200 {
			t.Fatal(w.Code)
		}
	}
	if calls.Load() != 1 {
		t.Fatal("cache replay called paid provider")
	}
	if w := call("POST", "/uncertain/audio/0", "{}"); w.Code != 409 {
		t.Fatal(w.Code)
	}
	if calls.Load() != 2 {
		t.Fatal("hidden provider retry")
	}
	if w := call("POST", "/uncertain/audio/0", "{}"); w.Code != 409 {
		t.Fatal("uncertain call refunded or budget ignored", w.Code)
	}
	if calls.Load() != 2 {
		t.Fatal("over-budget network call")
	}
	if w := call("POST", "/cached/audio/0", "{}"); w.Code != 200 {
		t.Fatal("cache blocked by spent budget", w.Code)
	}
	if _, err := os.Stat(filepath.Join(filepath.Dir(cfg.historyPath), "dictations", "paid-months")); err != nil {
		t.Fatal("missing durable budget", err)
	}
}
