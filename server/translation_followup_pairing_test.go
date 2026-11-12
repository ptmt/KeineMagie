package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
)

func TestFollowupCurrentDraftIsBoundedUntrustedContext(t *testing.T) {
	calls := 0
	_, h, browser, _, store := followupFixture(t, transportFunc(func(r *http.Request) (*http.Response, error) {
		if strings.Contains(r.URL.Path, "models") {
			return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(`{"models":[{"slug":"offered","visibility":"list"}]}`))}, nil
		}
		calls++
		var body struct {
			Instructions string `json:"instructions"`
			Input        []struct {
				Role    string `json:"role"`
				Content string `json:"content"`
			} `json:"input"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		encoded, _ := json.Marshal(body.Input)
		if !strings.Contains(string(encoded), "current_source") || !strings.Contains(string(encoded), "user-edited 😀") || strings.Contains(body.Instructions, "user-edited 😀") {
			t.Fatal("draft missing or promoted to trusted instruction")
		}
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(accountTranslationSSE(`{"answer":"Draft context understood","revised_text":null,"revised_source_text":null}`, true, "response.completed")))}, nil
	}))
	body := strings.TrimSuffix(followupValidBody, "}") + `,"current_source":"source's 😀\n","current_translation":"user-edited 😀\n"}`
	if w := followupCall(h, browser, body); w.Code != 201 {
		t.Fatalf("draft rejected %d %s", w.Code, w.Body.String())
	}
	if w := followupCall(h, browser, body); w.Code != 200 || calls != 1 {
		t.Fatal("same draft retry not idempotent")
	}
	if w := followupCall(h, browser, strings.Replace(body, "user-edited", "different", 1)); w.Code != 409 || calls != 1 {
		t.Fatal("different draft reused committed request ID")
	}
	record, err := store.followupRecord("saved", nil)
	if err != nil || record.Text != "лук" || record.Translation != "Zwiebel" {
		t.Fatal("original overwritten")
	}
	for _, draft := range []string{`,"current_source":"only source"`, `,"current_source":"` + strings.Repeat("😀", 8001) + `","current_translation":"x"`, `,"current_source":"x","current_translation":"` + strings.Repeat("😀", 8001) + `"`} {
		bad := strings.TrimSuffix(followupValidBody, "}") + draft + "}"
		if w := followupCall(h, browser, bad); w.Code != 400 {
			t.Fatalf("invalid draft accepted %d", w.Code)
		}
	}
}

func TestFollowupRejectsUnpairedOrInvalidSourceRevision(t *testing.T) {
	for _, output := range []string{
		`{"answer":"x","revised_text":"y"}`,
		`{"answer":"x","revised_text":null,"revised_source_text":"changed"}`,
		`{"answer":"x","revised_text":"y","revised_source_text":" "}`,
		`{"answer":"x","revised_text":"y","revised_source_text":17}`,
		`{"answer":"x","revised_text":"y","revised_source_text":null,"revised_source_text":null}`,
		`{"answer":"x","revised_text":"y","revised_source_text":"` + strings.Repeat("😀", 8001) + `"}`,
	} {
		if _, _, _, err := decodeClarification(output); err == nil {
			t.Fatal("invalid source accepted")
		}
	}
	// Old saved records predate the new field, not the new provider contract.
	var old translationFollowup
	if err := json.Unmarshal([]byte(`{"request_id":"old","question":"q","answer":"a","revised_text":"old proposal"}`), &old); err != nil || old.RevisedSourceText != nil {
		t.Fatal("old record incompatible")
	}
}

func TestFollowupPairedSourceSuggestion(t *testing.T) {
	for _, direction := range [][2]string{{"ru", "de"}, {"de", "ru"}, {"de", "de"}} {
		t.Run(direction[0]+"-"+direction[1], func(t *testing.T) {
			p := &providerService{client: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
				var body map[string]any
				if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
					t.Fatal(err)
				}
				instructions := body["instructions"].(string)
				for _, rule := range []string{"revised_source_text", "source_language", "Do not expand", "interface_locale"} {
					if !strings.Contains(instructions, rule) {
						t.Errorf("missing pairing rule %s", rule)
					}
				}
				schema := body["text"].(map[string]any)["format"].(map[string]any)["schema"].(map[string]any)
				if schema["properties"].(map[string]any)["revised_source_text"] == nil {
					t.Error("missing strict source schema")
				}
				return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(accountTranslationSSE(`{"answer":"A broader wording, not applied.","revised_text":"Paired output 😀\n","revised_source_text":"Paired source's 😀\n"}`, true, "response.completed")))}, nil
			})}}
			record := translationRecord{translationInput: translationInput{Text: "original", SourceLanguage: direction[0], TargetLanguage: direction[1]}, translationResult: translationResult{Translation: "original output"}}
			answer, revision, source, err := p.clarify(context.Background(), "synthetic", "offered", record, followupInput{Question: "mixed русский Deutsch?", Locale: "fr"})
			if err != nil || answer == "" || revision == nil || *revision != "Paired output 😀\n" || source == nil || *source != "Paired source's 😀\n" {
				t.Fatalf("pair lost %q %v %v %v", answer, revision, source, err)
			}
		})
	}
}
