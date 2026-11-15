package main

import (
	"context"
	"encoding/base64"
	"golang.org/x/net/websocket"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// Synthetic WebSocket events/PCM; not OpenAI speech or billing evidence.
func TestDictationRealtimeSyntheticTransport(t *testing.T) {
	for _, transcript := range []string{"Heute scheint die Sonne.", "Heute scheint Sonne.", "extra", "Ich kann diese Anfrage nicht erfüllen.", "missing-transcript", "incomplete", "cancelled", "overflow", "bad-base64", "wrong-response", "provider-error"} {
		t.Run(transcript, func(t *testing.T) {
			server := httptest.NewServer(websocket.Handler(func(ws *websocket.Conn) {
				defer ws.Close()
				if ws.Request().Header.Get("Authorization") != "Bearer synthetic-key" {
					t.Error("missing server credential")
				}
				websocket.JSON.Send(ws, map[string]any{"type": "session.created"})
				var update map[string]any
				if err := websocket.JSON.Receive(ws, &update); err != nil {
					t.Error(err)
					return
				}
				session := update["session"].(map[string]any)
				if session["type"] != "realtime" || session["max_output_tokens"] != float64(100) {
					t.Error("unbounded session", session)
				}
				websocket.JSON.Send(ws, map[string]any{"type": "session.updated"})
				var item map[string]any
				websocket.JSON.Receive(ws, &item)
				if item["type"] != "conversation.item.create" {
					t.Error("missing source")
				}
				websocket.JSON.Send(ws, map[string]any{"type": "conversation.item.done"})
				var response map[string]any
				websocket.JSON.Receive(ws, &response)
				if response["type"] != "response.create" {
					t.Error("missing explicit generation")
				}
				if transcript == "provider-error" {
					websocket.JSON.Send(ws, map[string]any{"type": "error"})
					return
				}
				websocket.JSON.Send(ws, map[string]any{"type": "response.created", "response": map[string]any{"id": "r"}})
				delta := base64.StdEncoding.EncodeToString(make([]byte, 480))
				if transcript == "overflow" {
					delta = base64.StdEncoding.EncodeToString(make([]byte, 480002))
				}
				if transcript == "bad-base64" {
					delta = "!!!"
				}
				responseID := "r"
				if transcript == "wrong-response" {
					responseID = "wrong"
				}
				websocket.JSON.Send(ws, map[string]any{"type": "response.output_audio.delta", "response_id": responseID, "item_id": "i", "delta": delta})
				websocket.JSON.Send(ws, map[string]any{"type": "response.output_audio.done", "response_id": "r", "item_id": "i"})
				if transcript != "missing-transcript" {
					websocket.JSON.Send(ws, map[string]any{"type": "response.output_audio_transcript.done", "response_id": "r", "item_id": "i", "transcript": transcript})
				}
				status := "completed"
				if transcript == "incomplete" || transcript == "cancelled" {
					status = transcript
				}
				websocket.JSON.Send(ws, map[string]any{"type": "response.done", "response": map[string]any{"id": "r", "status": status, "usage": map[string]any{"input_tokens": 10, "output_tokens": 10}}})
			}))
			defer server.Close()
			reported := false
			config := dictationOpenAIConfig{usage: func(u dictationSpeechUsage) error { reported = true; return nil }, key: "synthetic-key", model: "gpt-realtime-2.1-mini", voice: "marin", seconds: 10, tokens: 100, timeout: 10}
			b, err := dictationRealtime(context.Background(), config, "Heute scheint die Sonne.", "ws"+strings.TrimPrefix(server.URL, "http"))
			if !reported && transcript != "provider-error" && transcript != "overflow" && transcript != "bad-base64" && transcript != "wrong-response" {
				t.Error("completed usage not recorded, including mismatch")
			}
			if transcript == "Heute scheint die Sonne." {
				if err != nil || len(b) != 524 || string(b[:4]) != "RIFF" {
					t.Fatalf("%d %v", len(b), err)
				}
			} else if err == nil || len(b) != 0 {
				t.Fatal("rewritten narration published")
			}
		})
	}
}

func TestDictationRealtimeCancellationNoRetry(t *testing.T) {
	var calls atomic.Int32
	closed := make(chan struct{}, 1)
	server := httptest.NewServer(websocket.Handler(func(ws *websocket.Conn) {
		calls.Add(1)
		defer ws.Close()
		defer func() { closed <- struct{}{} }()
		var raw string
		websocket.Message.Receive(ws, &raw) // peer intentionally never sends session.created
	}))
	defer server.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	b, err := dictationRealtime(ctx, dictationOpenAIConfig{key: "synthetic", timeout: 10}, "Hallo.", "ws"+strings.TrimPrefix(server.URL, "http"))
	if err == nil || len(b) != 0 {
		t.Fatal("canceled audio accepted")
	}
	select {
	case <-closed:
	case <-time.After(time.Second):
		t.Fatal("socket did not close")
	}
	if calls.Load() != 1 {
		t.Fatal("provider request retried")
	}
}

func TestDictationOpenAIConfigurationFailClosed(t *testing.T) {
	t.Setenv("DICTATION_TTS_PROVIDER", "openai-realtime")
	t.Setenv("DICTATION_OPENAI_API_KEY", "synthetic-key")
	t.Setenv("DICTATION_OPENAI_API_KEY_FILE", "")
	for k, v := range map[string]string{"MODEL": "gpt-realtime-2.1-mini", "VOICE": "marin", "MAX_CHARS": "1800", "MAX_SECONDS": "120", "MAX_OUTPUT_TOKENS": "4096", "TIMEOUT_SECONDS": "150", "DAILY_CHARS": "3600", "DAILY_SECONDS": "240", "DAILY_REQUESTS": "2", "CONCURRENCY": "1"} {
		t.Setenv("DICTATION_OPENAI_"+k, v)
	}
	if _, err := dictationLoadOpenAI(); err != nil {
		t.Fatal(err)
	}
	t.Setenv("DICTATION_OPENAI_DAILY_CHARS", "")
	if _, err := dictationLoadOpenAI(); err == nil {
		t.Fatal("missing budget accepted")
	}
	t.Setenv("DICTATION_OPENAI_DAILY_CHARS", "3600")
	t.Setenv("DICTATION_OPENAI_MODEL", "tts-1")
	if _, err := dictationLoadOpenAI(); err == nil {
		t.Fatal("silent model substitution accepted")
	}
}

func TestDictationNarrationWords(t *testing.T) {
	for _, tc := range []struct {
		source, transcript string
		want               bool
	}{
		{"Heute scheint die Sonne.", "heute scheint die Sonne!", true},
		{"Grüße, Café!", "Grüße Cafe\u0301", true},
		{"Heute scheint die Sonne.", "Heute scheint Sonne.", false},
		{"Heute scheint die Sonne.", "Gerne! Heute scheint die Sonne.", false},
		{"Wir gehen heim.", "Wir gehen nach Hause.", false},
		{"123", "einhundertdreiundzwanzig", false},
		{"", "", false},
	} {
		if got := dictationNarrationMatches(tc.source, tc.transcript); got != tc.want {
			t.Errorf("source %q transcript %q: %v", tc.source, tc.transcript, got)
		}
	}
}
