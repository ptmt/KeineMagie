package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"

	"golang.org/x/net/websocket"
)

func TestDictationRealtimeSettlementReceiptBoundary(t *testing.T) {
	for _, mode := range []string{"complete", "incomplete", "cancelled", "wrong-response", "missing-usage", "missing-breakdown", "negative", "overflow", "disconnect-before-receipt", "receipt-write-failure"} {
		t.Run(mode, func(t *testing.T) {
			root := t.TempDir()
			ticket, err := dictationReserveMonthly(root)
			if err != nil {
				t.Fatal(err)
			}
			u := dictationSpeechUsage{InputTokens: 10, OutputTokens: 20}
			u.Input.TextTokens = 10
			u.Output.AudioTokens = 20
			var calls atomic.Int32
			server := httptest.NewServer(websocket.Handler(func(ws *websocket.Conn) {
				calls.Add(1)
				defer ws.Close()
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
				websocket.JSON.Send(ws, map[string]any{"type": "response.created", "response": map[string]any{"id": "r"}})
				for _, event := range []map[string]any{
					{"type": "response.output_audio.delta", "response_id": "r", "item_id": "i", "delta": base64.StdEncoding.EncodeToString(make([]byte, 480))},
					{"type": "response.output_audio.done", "response_id": "r", "item_id": "i"},
					{"type": "response.output_audio_transcript.done", "response_id": "r", "item_id": "i", "transcript": "Hallo."},
				} {
					websocket.JSON.Send(ws, event)
				}
				if mode == "disconnect-before-receipt" {
					return
				}
				response := map[string]any{"id": "r", "status": "completed", "usage": u}
				switch mode {
				case "incomplete", "cancelled":
					response["status"] = mode
				case "wrong-response":
					response["id"] = "foreign"
				case "missing-usage":
					delete(response, "usage")
				case "missing-breakdown":
					response["usage"] = map[string]any{"input_tokens": 0, "output_tokens": 0}
				case "negative":
					bad := u
					bad.Input.TextTokens = -1
					response["usage"] = bad
				case "overflow":
					bad := u
					bad.Input.TextTokens = 9223372036854775807
					bad.Input.AudioTokens = 11
					response["usage"] = bad
				}
				websocket.JSON.Send(ws, map[string]any{"type": "response.done", "response": response})
			}))
			defer server.Close()
			cfg := dictationOpenAIConfig{key: "synthetic", model: "gpt-realtime-2.1-mini", seconds: 10, tokens: 100, timeout: 3}
			cfg.usage = func(u dictationSpeechUsage) error { return dictationRecordUsage(root, ticket, u) }
			cfg.completedUsage = func(id string, u dictationSpeechUsage) error {
				if mode == "receipt-write-failure" {
					return os.ErrPermission
				}
				return dictationRecordCompletedUsage(root, ticket, id, u)
			}
			_, err = dictationRealtime(context.Background(), cfg, "Hallo.", "ws"+strings.TrimPrefix(server.URL, "http"))
			if mode == "complete" && err != nil {
				t.Fatal(err)
			}
			if calls.Load() != 1 {
				t.Fatal("automatic provider retry")
			}
			b, e := os.ReadFile(filepath.Join(root, "paid-months", ticket.month+".json"))
			if e != nil {
				t.Fatal(e)
			}
			var d dictationMonthlyLedger
			if e = json.Unmarshal(b, &d); e != nil {
				t.Fatal(e)
			}
			got, e := dictationMonthlyAccounted(&d, ticket.month)
			if e != nil {
				t.Fatal(e)
			}
			want := dictationAttemptMicroUSD
			if mode == "complete" {
				want, _ = dictationUsageMicroUSD(u)
			}
			if got != want {
				t.Fatalf("charged=%d want=%d", got, want)
			}
		})
	}
}
