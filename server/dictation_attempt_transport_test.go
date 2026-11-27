package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"golang.org/x/net/websocket"
)

// Local synthetic wire fixture; every event goes through dictationRealtime.
func dictationAttemptWire(t *testing.T, mode string, onCreate func(), calls *atomic.Int32) string {
	t.Helper()
	server := httptest.NewServer(websocket.Handler(func(ws *websocket.Conn) {
		calls.Add(1)
		defer ws.Close()
		if mode == "pre-send-error" {
			websocket.JSON.Send(ws, map[string]any{"type": "error"})
			return
		}
		websocket.JSON.Send(ws, map[string]any{"type": "session.created"})
		var v map[string]any
		for _, kind := range []string{"session.updated", "conversation.item.done"} {
			if websocket.JSON.Receive(ws, &v) != nil {
				return
			}
			websocket.JSON.Send(ws, map[string]any{"type": kind})
		}
		if websocket.JSON.Receive(ws, &v) != nil {
			return
		}
		if v["type"] != "response.create" {
			return
		}
		if onCreate != nil {
			onCreate()
		}
		if mode == "disconnect" {
			return
		}
		if mode == "provider-error" {
			websocket.JSON.Send(ws, map[string]any{"type": "error"})
			return
		}
		websocket.JSON.Send(ws, map[string]any{"type": "response.created", "response": map[string]any{"id": "synthetic-r"}})
		delta := base64.StdEncoding.EncodeToString(make([]byte, 480))
		transcript := "Hallo."
		if mode == "invalid-base64" {
			delta = "!"
		}
		if mode == "oversize-audio" {
			delta = base64.StdEncoding.EncodeToString(make([]byte, 480002))
		}
		if mode == "wrong-narration" {
			transcript = "Falsch."
		}
		for _, e := range []map[string]any{
			{"type": "response.output_audio.delta", "response_id": "synthetic-r", "item_id": "i", "delta": delta},
			{"type": "response.output_audio.done", "response_id": "synthetic-r", "item_id": "i"},
			{"type": "response.output_audio_transcript.done", "response_id": "synthetic-r", "item_id": "i", "transcript": transcript},
		} {
			if mode != "no-audio" {
				if websocket.JSON.Send(ws, e) != nil {
					return
				}
			}
		}
		if mode == "partial" {
			return
		}
		u := dictationSpeechUsage{InputTokens: 10, OutputTokens: 20}
		u.Input.TextTokens = 10
		u.Output.AudioTokens = 20
		status := "completed"
		id := "synthetic-r"
		if mode == "cancelled" {
			status = "cancelled"
		}
		if mode == "wrong-response" {
			id = "foreign"
		}
		websocket.JSON.Send(ws, map[string]any{"type": "response.done", "response": map[string]any{"id": id, "status": status, "usage": u}})
	}))
	t.Cleanup(server.Close)
	return "ws" + strings.TrimPrefix(server.URL, "http")
}

func TestDictationAttemptHTTPRealTransport(t *testing.T) {
	for _, mode := range []string{"complete", "wrong-narration", "no-audio", "invalid-base64", "oversize-audio", "cancel-after-receipt", "cancel-before-persist", "pre-send-error", "disconnect", "provider-error", "partial", "cancelled", "wrong-response", "receipt-write-failure"} {
		t.Run(mode, func(t *testing.T) {
			dictationPaidTestConfig(t)
			cfg, call := dictationTestAPI(t)
			if w := call("POST", "", `{"id":"wire","title":"Test","text":"Hallo.","language":"de"}`); w.Code != 200 {
				t.Fatal(w.Code)
			}
			root := filepath.Join(filepath.Dir(cfg.historyPath), "dictations")
			var calls atomic.Int32
			endpoint := dictationAttemptWire(t, mode, func() {
				if err := dictationAttemptLedgers(root, func(_ string, d *dictationMonthlyLedger) error {
					if len(d.Entries) != 1 || d.Entries[0].Attempt.State != "attempted" || d.Entries[0].Attempt.Day == "" {
						t.Error("response.create before durable admission")
					}
					return nil
				}); err != nil {
					t.Error(err)
				}
			}, &calls)
			cfg.dictationSpeech = func(ctx context.Context, c dictationOpenAIConfig, text string) ([]byte, error) {
				ctx, cancel := context.WithCancel(ctx)
				defer cancel()
				original := c.completedUsage
				c.completedUsage = func(id string, u dictationSpeechUsage) error {
					if mode == "receipt-write-failure" {
						return os.ErrPermission
					}
					if mode == "cancel-before-persist" {
						cancel()
					}
					err := original(id, u)
					if mode == "cancel-after-receipt" {
						cancel()
					}
					return err
				}
				return dictationRealtime(ctx, c, text, endpoint)
			}
			w := call("POST", "/wire/audio/0", "{}")
			if mode == "complete" {
				if w.Code != 200 {
					t.Fatal(w.Code, w.Body)
				}
			} else if w.Code == 200 {
				t.Fatal("invalid audio published")
			}
			if mode != "complete" && mode != "pre-send-error" && !strings.Contains(w.Body.String(), "speech_recovery_needed") {
				t.Errorf("first failed attempt lacks recovery status: %d %s", w.Code, w.Body)
			}
			completed := mode == "complete" || mode == "wrong-narration" || mode == "no-audio" || mode == "invalid-base64" || mode == "oversize-audio" || mode == "cancel-after-receipt" || mode == "cancel-before-persist"
			wantState := "attempted"
			wantCharge := dictationAttemptMicroUSD
			if completed {
				wantState = "completed"
				wantCharge = 406
			}
			if mode == "pre-send-error" {
				wantState = "released"
				wantCharge = 0
			}
			if err := dictationAttemptLedgers(root, func(month string, d *dictationMonthlyLedger) error {
				total, e := dictationMonthlyAccounted(d, month)
				if e != nil || total != wantCharge || d.Entries[0].Attempt.State != wantState {
					t.Errorf("state=%s charge=%d want=%s/%d err=%v", d.Entries[0].Attempt.State, total, wantState, wantCharge, e)
				}
				return nil
			}); err != nil {
				t.Fatal(err)
			}
			before := calls.Load()
			again := call("POST", "/wire/audio/0", "{}")
			if mode == "pre-send-error" {
				if calls.Load() != before+1 {
					t.Fatal("safe retry blocked")
				}
			} else {
				if calls.Load() != before {
					t.Fatal("repeated POST called provider")
				}
				if mode == "complete" {
					if again.Code != 200 {
						t.Fatal("cache", again.Code)
					}
				} else if again.Code != 409 || !strings.Contains(again.Body.String(), "speech_recovery_needed") {
					t.Fatal("missing recovery feedback", again.Code, again.Body)
				}
			}
			if _, e := os.Stat(filepath.Join(root, "paid-budget.json")); !os.IsNotExist(e) {
				t.Fatal("new attempt changed legacy daily file", e)
			}
			// Reading the DTO cannot expose global holds or unknown/foreign owners.
			list := call("GET", "", "")
			var body map[string]any
			if json.Unmarshal(list.Body.Bytes(), &body) != nil {
				t.Fatal("DTO")
			}
		})
	}
}

func TestDictationAttemptConcurrentHTTPProducer(t *testing.T) {
	dictationPaidTestConfig(t)
	cfg, call := dictationTestAPI(t)
	if w := call("POST", "", `{"id":"parallel","title":"Test","text":"Hallo.","language":"de"}`); w.Code != 200 {
		t.Fatal(w.Code)
	}
	entered, release := make(chan struct{}), make(chan struct{})
	var calls atomic.Int32
	endpoint := dictationAttemptWire(t, "provider-error", func() { close(entered); <-release }, &calls)
	cfg.dictationSpeech = func(ctx context.Context, c dictationOpenAIConfig, text string) ([]byte, error) {
		return dictationRealtime(ctx, c, text, endpoint)
	}
	done := make(chan *httptest.ResponseRecorder, 1)
	go func() { done <- call("POST", "/parallel/audio/0", "{}") }()
	select {
	case <-entered:
	case <-time.After(3 * time.Second):
		t.Fatal("wire never entered")
	}
	for i := 0; i < 4; i++ {
		if w := call("POST", "/parallel/audio/0", "{}"); w.Code != 429 || !strings.Contains(w.Body.String(), "speech_engine_busy") {
			t.Fatal("concurrent producer admitted", w.Code, w.Body)
		}
	}
	close(release)
	if w := <-done; w.Code != 409 {
		t.Fatal(w.Code, w.Body)
	}
	for i := 0; i < 4; i++ {
		if w := call("POST", "/parallel/audio/0", "{}"); w.Code != 409 {
			t.Fatal(w.Code, w.Body)
		}
	}
	if calls.Load() != 1 {
		t.Fatal("duplicate paid wire calls", calls.Load())
	}
}

func TestDictationAttemptLogoutBeforeIntentReleases(t *testing.T) {
	dictationPaidTestConfig(t)
	cfg, call := dictationTestAPI(t)
	if w := call("POST", "", `{"id":"logout","title":"Test","text":"Hallo.","language":"de"}`); w.Code != 200 {
		t.Fatal(w.Code)
	}
	var calls, sent atomic.Int32
	endpoint := dictationAttemptWire(t, "provider-error", func() { sent.Add(1) }, &calls)
	cfg.dictationSpeech = func(ctx context.Context, c dictationOpenAIConfig, text string) ([]byte, error) {
		original := c.beforeAttempt
		c.beforeAttempt = func(attemptCtx context.Context) error {
			if err := cfg.auth.store.lock.locked(func() error {
				d, e := cfg.auth.store.read()
				if e != nil {
					return e
				}
				for k := range d.Sessions {
					delete(d.Sessions, k)
				}
				return cfg.auth.store.write(d)
			}); err != nil {
				return err
			}
			return original(attemptCtx)
		}
		return dictationRealtime(ctx, c, text, endpoint)
	}
	w := call("POST", "/logout/audio/0", "{}")
	if w.Code != 401 {
		t.Errorf("logout before intent: %d %s", w.Code, w.Body)
	}
	if sent.Load() != 0 {
		t.Error("logged-out producer sent response.create")
	}
	root := filepath.Join(filepath.Dir(cfg.historyPath), "dictations")
	if err := dictationAttemptLedgers(root, func(month string, d *dictationMonthlyLedger) error {
		total, e := dictationMonthlyAccounted(d, month)
		if e != nil || total != 0 || d.Entries[0].Attempt.State != "released" {
			t.Error("logout before send charged", total, e)
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
}

func TestDictationAttemptTransportCancelBeforeIntentReleases(t *testing.T) {
	dictationPaidTestConfig(t)
	cfg, call := dictationTestAPI(t)
	if w := call("POST", "", `{"id":"cancel-intent","title":"Test","text":"Hallo.","language":"de"}`); w.Code != 200 {
		t.Fatal(w.Code)
	}
	var calls atomic.Int32
	endpoint := dictationAttemptWire(t, "provider-error", nil, &calls)
	cfg.dictationSpeech = func(ctx context.Context, c dictationOpenAIConfig, text string) ([]byte, error) {
		ctx, cancel := context.WithCancel(ctx)
		defer cancel()
		original := c.beforeAttempt
		c.beforeAttempt = func(attemptCtx context.Context) error { cancel(); return original(attemptCtx) }
		return dictationRealtime(ctx, c, text, endpoint)
	}
	call("POST", "/cancel-intent/audio/0", "{}")
	root := filepath.Join(filepath.Dir(cfg.historyPath), "dictations")
	if err := dictationAttemptLedgers(root, func(month string, d *dictationMonthlyLedger) error {
		total, e := dictationMonthlyAccounted(d, month)
		if e != nil || total != 0 || d.Entries[0].Attempt.State != "released" {
			t.Error("known cancellation before intent charged", total, e)
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
}

func TestDictationAttemptDialFailureIsNeverSent(t *testing.T) {
	for _, mode := range []string{"handshake-rejected", "dial-refused"} {
		t.Run(mode, func(t *testing.T) {
			dictationPaidTestConfig(t)
			cfg, call := dictationTestAPI(t)
			if w := call("POST", "", `{"id":"dial","title":"Test","text":"Hallo.","language":"de"}`); w.Code != 200 {
				t.Fatal(w.Code)
			}
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(503) }))
			defer server.Close()
			endpoint := "ws" + strings.TrimPrefix(server.URL, "http")
			if mode == "dial-refused" {
				server.Close()
			}
			cfg.dictationSpeech = func(ctx context.Context, c dictationOpenAIConfig, text string) ([]byte, error) {
				return dictationRealtime(ctx, c, text, endpoint)
			}
			for i := 0; i < 4; i++ {
				if w := call("POST", "/dial/audio/0", "{}"); w.Code != 503 {
					t.Fatal("dial failure consumed allowance", w.Code, w.Body)
				}
			}
			root := filepath.Join(filepath.Dir(cfg.historyPath), "dictations")
			if err := dictationAttemptLedgers(root, func(month string, d *dictationMonthlyLedger) error {
				total, e := dictationMonthlyAccounted(d, month)
				if e != nil || total != 0 || len(d.Entries) != 4 {
					t.Error("dial failure charged", total, e)
				}
				return nil
			}); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestDictationCachedPOSTSurvivesUnrecognizedLedger(t *testing.T) {
	dictationPaidTestConfig(t)
	cfg, call := dictationTestAPI(t)
	if w := call("POST", "", `{"id":"cache","title":"Test","text":"Hallo.","language":"de"}`); w.Code != 200 {
		t.Fatal(w.Code)
	}
	var calls atomic.Int32
	endpoint := dictationAttemptWire(t, "complete", nil, &calls)
	cfg.dictationSpeech = func(ctx context.Context, c dictationOpenAIConfig, text string) ([]byte, error) {
		return dictationRealtime(ctx, c, text, endpoint)
	}
	if w := call("POST", "/cache/audio/0", "{}"); w.Code != 200 {
		t.Fatal(w.Code, w.Body)
	}
	root := filepath.Join(filepath.Dir(cfg.historyPath), "dictations")
	paths, _ := filepath.Glob(filepath.Join(root, "paid-months", "*.json"))
	raw, _ := os.ReadFile(paths[0])
	var d map[string]any
	json.Unmarshal(raw, &d)
	d["attempt_policy"] = 2
	raw, _ = json.Marshal(d)
	if err := os.WriteFile(paths[0], raw, 0600); err != nil {
		t.Fatal(err)
	}
	for _, method := range []string{"GET", "POST"} {
		body := ""
		if method == "POST" {
			body = "{}"
		}
		if w := call(method, "/cache/audio/0", body); w.Code != 200 {
			t.Errorf("cached %s blocked by ledger: %d", method, w.Code)
		}
	}
	after, _ := os.ReadFile(paths[0])
	if string(raw) != string(after) || calls.Load() != 1 {
		t.Fatal("cache changed accounting or called provider")
	}
}

func TestDictationAttemptLogoutAfterReceiptKeepsSettlementAnd401(t *testing.T) {
	dictationPaidTestConfig(t)
	cfg, call := dictationTestAPI(t)
	if w := call("POST", "", `{"id":"logout-done","title":"Test","text":"Hallo.","language":"de"}`); w.Code != 200 {
		t.Fatal(w.Code)
	}
	var calls atomic.Int32
	endpoint := dictationAttemptWire(t, "complete", nil, &calls)
	cfg.dictationSpeech = func(ctx context.Context, c dictationOpenAIConfig, text string) ([]byte, error) {
		original := c.completedUsage
		c.completedUsage = func(id string, u dictationSpeechUsage) error {
			if err := original(id, u); err != nil {
				return err
			}
			return cfg.auth.store.lock.locked(func() error {
				d, e := cfg.auth.store.read()
				if e != nil {
					return e
				}
				for k := range d.Sessions {
					delete(d.Sessions, k)
				}
				return cfg.auth.store.write(d)
			})
		}
		return dictationRealtime(ctx, c, text, endpoint)
	}
	if w := call("POST", "/logout-done/audio/0", "{}"); w.Code != 401 {
		t.Error("publication must preserve unauthorized status", w.Code, w.Body)
	}
	root := filepath.Join(filepath.Dir(cfg.historyPath), "dictations")
	if err := dictationAttemptLedgers(root, func(month string, d *dictationMonthlyLedger) error {
		total, e := dictationMonthlyAccounted(d, month)
		if e != nil || total != 406 || d.Entries[0].Attempt.State != "completed" {
			t.Error("logout lost receipt", total, e)
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
}
