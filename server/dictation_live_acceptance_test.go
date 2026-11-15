package main

import (
	"context"
	"encoding/json"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Explicit opt-in only; never uses ambient credentials or automatically retries.
// Store is durable and private, outside the source tree and regenerable scratch.
func TestDictationOneAuthorizedLiveAcceptance(t *testing.T) {
	if os.Getenv("KM_DICTATION_ONE_AUTHORIZED_LIVE") != "2026-11-15-short-german" {
		t.Skip("paid acceptance requires explicit operator authorization")
	}
	root := "/Users/tinyserve/.local/share/keinemagie/dictation-openai-acceptance"
	if err := os.MkdirAll(root, 0700); err != nil {
		t.Fatal("private store unavailable")
	}
	marker, err := os.OpenFile(filepath.Join(root, "one-authorized-attempt"), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		t.Fatal("one-attempt marker exists or unavailable; no automatic paid retry")
	}
	marker.Sync()
	marker.Close()
	t.Setenv("DICTATION_OPENAI_API_KEY", "")
	t.Setenv("DICTATION_OPENAI_API_KEY_FILE", "/Users/tinyserve/.config/keinemagie/secrets/dictation-openai.key")
	t.Setenv("DICTATION_TTS_PROVIDER", "openai-realtime")
	for k, v := range map[string]string{"MODEL": "gpt-realtime-2.1-mini", "VOICE": "marin", "MAX_CHARS": "100", "MAX_SECONDS": "12", "MAX_OUTPUT_TOKENS": "256", "TIMEOUT_SECONDS": "45", "DAILY_CHARS": "100", "DAILY_SECONDS": "12", "DAILY_REQUESTS": "1", "CONCURRENCY": "1"} {
		t.Setenv("DICTATION_OPENAI_"+k, v)
	}
	cfg := &serverConfig{authPath: filepath.Join(root, "auth.json"), historyPath: filepath.Join(root, "history.json")}
	calls := 0
	var usage *dictationSpeechUsage
	cfg.dictationSpeech = func(ctx context.Context, c dictationOpenAIConfig, text string) ([]byte, error) {
		calls++
		if calls != 1 {
			t.Fatal("unexpected second provider invocation")
		}
		original := c.usage
		c.usage = func(u dictationSpeechUsage) error { usage = &u; return original(u) }
		return dictationRealtime(ctx, c, text, "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1-mini")
	}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal("handler setup failed")
	}
	token, _, err := cfg.auth.store.create("acceptance-fixture-only", time.Now())
	if err != nil {
		t.Fatal("fixture identity setup failed")
	}
	call := func(method, path, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, "/v1/learning/dictations"+path, strings.NewReader(body))
		r.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	const fixture = "Heute scheint die Sonne."
	report := map[string]any{"model": "gpt-realtime-2.1-mini", "voice": "marin", "fixture": fixture, "max_seconds": 12, "max_output_tokens": 256, "automatic_retries": 0, "invoice_cost": "unknown; reported usage estimate is not an invoice"}
	defer func() {
		report["provider_invocations"] = calls
		report["usage"] = usage
		b, _ := json.MarshalIndent(report, "", "  ")
		os.WriteFile(filepath.Join(root, "result.json"), b, 0600)
	}()
	if w := call("POST", "", `{"id":"short-german","title":"Synthetic acceptance fixture","text":"Heute scheint die Sonne.","language":"de"}`); w.Code != 200 {
		t.Fatal("fixture creation failed")
	}
	started := time.Now()
	w := call("POST", "/short-german/audio/0", "{}")
	report["elapsed_ms"] = time.Since(started).Milliseconds()
	report["prepare_http"] = w.Code
	if w.Code != 200 {
		report["safe_error"] = strings.TrimSpace(w.Body.String())
		t.Fatalf("real acceptance failed safely: HTTP %d; no retries", w.Code)
	}
	report["completed_transcript_lexical_gate"] = true
	audio := call("GET", "/short-german/audio/0", "")
	if audio.Code != 200 {
		t.Fatal("cached asset unavailable")
	}
	if err := os.WriteFile(filepath.Join(root, "short-german.wav"), audio.Body.Bytes(), 0600); err != nil {
		t.Fatal("artifact write failed")
	}
	for i := 0; i < 3; i++ {
		if call("POST", "/short-german/audio/0", "{}").Code != 200 || call("GET", "/short-german/audio/0", "").Code != 200 {
			t.Fatal("cache replay failed")
		}
	}
	if calls != 1 {
		t.Fatal("cache replay invoked provider")
	}
	report["cached_prepare_and_get_pairs"] = 3
	report["extra_replay_provider_calls"] = 0
	if usage != nil {
		if cost, ok := dictationUsageMicroUSD(*usage); ok {
			report["reported_estimate_micro_usd"] = cost
		}
	}
}
