package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
)

// Synthetic Responses wire events, not captured credentials or live inference.
func accountTranslationSSE(output string, deltas bool, terminal string) string {
	var stream strings.Builder
	emit := func(kind string, fields map[string]any) {
		fields["type"] = kind
		data, _ := json.Marshal(fields)
		stream.WriteString("event: " + kind + "\ndata: " + string(data) + "\n\n")
	}
	emit("response.created", map[string]any{"response": map[string]any{"id": "resp_test", "status": "in_progress"}})
	if deltas {
		// Split even inside JSON escapes to exercise assembly before decoding.
		for _, r := range output {
			emit("response.output_text.delta", map[string]any{"item_id": "msg_test", "output_index": 0, "content_index": 0, "delta": string(r)})
		}
	}
	emit("response.output_text.done", map[string]any{"item_id": "msg_test", "output_index": 0, "content_index": 0, "text": output})
	if terminal != "" {
		status := "completed"
		if terminal != "response.completed" {
			status = "incomplete"
		}
		emit(terminal, map[string]any{"response": map[string]any{"id": "resp_test", "status": status, "output": []any{map[string]any{"type": "message", "role": "assistant", "content": []any{map[string]any{"type": "output_text", "text": output}}}}}})
	}
	return stream.String()
}

func TestAccountTranslationOutputValidation(t *testing.T) {
	cases := []struct {
		name, output, want string
		noDeltas           bool
		terminal           string
		invalid            bool
	}{
		{name: "multiline escapes unicode", output: `{"text":"  Zeile 1\n\"Привет\" \\ Pfad\t😀\n "}`, want: "  Zeile 1\n\"Привет\" \\ Pfad\t😀\n "},
		{name: "unicode escapes", output: `{"text":"\u041f\u0440\u0438\u0432\u0435\u0442 \ud83d\ude00"}`, want: "Привет 😀"},
		{name: "literal JSON translation", output: `{"text":"{\"text\":\"Es hat funktioniert.\"}"}`, want: `{"text":"Es hat funktioniert."}`},
		{name: "literal fenced translation", output: "{\"text\":\"```json\\n{\\\"text\\\":\\\"Hallo\\\"}\\n```\"}", want: "```json\n{\"text\":\"Hallo\"}\n```"},
		{name: "completed snapshot only", output: `{"text":"Es hat funktioniert."}`, want: "Es hat funktioniert.", noDeltas: true},
		{name: "plain violates requested schema", output: "Es hat funktioniert.", invalid: true},
		{name: "empty stream", output: "", invalid: true},
		{name: "empty text", output: `{"text":""}`, invalid: true},
		{name: "blank text", output: `{"text":" \n\t"}`, invalid: true},
		{name: "null text", output: `{"text":null}`, invalid: true},
		{name: "missing text", output: `{}`, invalid: true},
		{name: "wrong type", output: `{"text":3}`, invalid: true},
		{name: "unknown field", output: `{"text":"Hallo","extra":true}`, invalid: true},
		{name: "case sensitive schema", output: `{"Text":"Hallo"}`, invalid: true},
		{name: "duplicate field", output: `{"text":"first","text":"second"}`, invalid: true},
		{name: "malformed", output: `{"text":"Hallo`, invalid: true},
		{name: "mixed prefix", output: `Translation: {"text":"Hallo"}`, invalid: true},
		{name: "mixed suffix", output: `{"text":"Hallo"} explanation`, invalid: true},
		{name: "two objects", output: `{"text":"Hallo"}{"text":"Welt"}`, invalid: true},
		{name: "fenced envelope", output: "```json\n{\"text\":\"Hallo\"}\n```", invalid: true},
		{name: "valid but interrupted", output: `{"text":"Hallo"}`, terminal: "none", invalid: true},
		{name: "valid but failed", output: `{"text":"Hallo"}`, terminal: "response.failed", invalid: true},
		{name: "valid but incomplete", output: `{"text":"Hallo"}`, terminal: "response.incomplete", invalid: true},
		{name: "valid but refused", output: `{"text":"Hallo"}`, terminal: "response.refusal.done", invalid: true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			terminal := tc.terminal
			if terminal == "" {
				terminal = "response.completed"
			}
			if terminal == "none" {
				terminal = ""
			}
			p := &providerService{client: &http.Client{Transport: transportFunc(func(*http.Request) (*http.Response, error) {
				return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(accountTranslationSSE(tc.output, !tc.noDeltas, terminal)))}, nil
			})}}
			got, err := p.translate(context.Background(), "synthetic-token", "offered", translationInput{})
			if tc.invalid {
				if err == nil || got != "" {
					t.Fatalf("invalid result accepted: %q, %v", got, err)
				}
				return
			}
			if err != nil || got != tc.want {
				t.Fatalf("translation = %q, %v; want %q", got, err, tc.want)
			}
		})
	}
}

func TestAccountTranslationTerminalValidation(t *testing.T) {
	for _, tc := range []struct{ name, snapshot string }{
		{"mismatched snapshot", `{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"different"}]}]}`},
		{"terminal refusal", `{"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"No"}]}]}`},
		{"wrong terminal status", `{"status":"incomplete"}`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			wire := accountTranslationSSE(`{"text":"Hallo"}`, true, "") + "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":" + tc.snapshot + "}\n\n"
			p := &providerService{client: &http.Client{Transport: transportFunc(func(*http.Request) (*http.Response, error) {
				return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(wire))}, nil
			})}}
			if got, err := p.translate(context.Background(), "synthetic-token", "offered", translationInput{}); err == nil || got != "" {
				t.Fatalf("invalid completed response accepted: %q, %v", got, err)
			}
		})
	}
}

func TestAccountTranslationStructuredOutput(t *testing.T) {
	p := &providerService{client: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		var payload struct {
			Text struct {
				Format struct {
					Type   string         `json:"type"`
					Name   string         `json:"name"`
					Strict bool           `json:"strict"`
					Schema map[string]any `json:"schema"`
				} `json:"format"`
			} `json:"text"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatal(err)
		}
		format := payload.Text.Format
		if format.Type != "json_schema" || !format.Strict || format.Name == "" || format.Schema["additionalProperties"] != false {
			t.Errorf("missing strict Responses text schema")
		}
		return &http.Response{StatusCode: 200, Header: http.Header{"Content-Type": []string{"text/event-stream"}}, Body: io.NopCloser(strings.NewReader(accountTranslationSSE(`{"text":"Es hat funktioniert."}`, true, "response.completed")))}, nil
	})}}
	got, err := p.translate(context.Background(), "synthetic-token", "offered", translationInput{Text: "Получилось.", SourceLanguage: "ru", TargetLanguage: "de"})
	if err != nil || got != "Es hat funktioniert." {
		t.Fatalf("translation = %q, %v; want plain translated text", got, err)
	}
}
