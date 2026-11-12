package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
)

func TestFollowupPreservesAllTranslationDirections(t *testing.T) {
	for _, direction := range [][2]string{{"ru", "de"}, {"de", "ru"}, {"de", "de"}} {
		t.Run(direction[0]+"-"+direction[1], func(t *testing.T) {
			p := &providerService{client: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
				var payload struct {
					Instructions string `json:"instructions"`
					Input        []struct {
						Role    string `json:"role"`
						Content string `json:"content"`
					} `json:"input"`
					Text struct {
						Format struct {
							Type   string `json:"type"`
							Name   string `json:"name"`
							Strict bool   `json:"strict"`
						} `json:"format"`
					} `json:"text"`
				}
				if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
					t.Fatal(err)
				}
				if payload.Text.Format.Name != "translation_clarification" || !payload.Text.Format.Strict || payload.Text.Format.Type != "json_schema" {
					t.Fatal("not structured clarification")
				}
				var original map[string]string
				if err := json.Unmarshal([]byte(payload.Input[0].Content), &original); err != nil {
					t.Fatal(err)
				}
				if original["source_language"] != direction[0] || original["target_language"] != direction[1] || original["original_source"] != "Exact original\n😀" || original["original_translation"] != "Exact output\n😀" || original["interface_locale"] != "fr" {
					t.Fatalf("wrong association %v", original)
				}
				if len(payload.Input) != 4 || payload.Input[1].Role != "user" || payload.Input[2].Role != "assistant" || payload.Input[3].Role != "user" || payload.Input[3].Content != "Почему?" {
					t.Fatal("roles/thread lost")
				}
				if !strings.Contains(payload.Instructions, "German proofreading") || !strings.Contains(payload.Instructions, "language of the user's question") {
					t.Fatal("task/language lost")
				}
				return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(accountTranslationSSE(`{"answer":"Пояснение","revised_text":null}`, false, "response.completed")))}, nil
			})}}
			record := translationRecord{translationInput: translationInput{Text: "Exact original\n😀", SourceLanguage: direction[0], TargetLanguage: direction[1]}, translationResult: translationResult{Translation: "Exact output\n😀"}, Followups: []translationFollowup{{Question: "Первый вопрос", Answer: "Первый ответ"}}}
			answer, revision, err := p.clarify(context.Background(), "synthetic", "offered", record, followupInput{Question: "Почему?", Locale: "fr"})
			if err != nil || answer != "Пояснение" || revision != nil {
				t.Fatalf("answer %q %v", answer, err)
			}
		})
	}
}
