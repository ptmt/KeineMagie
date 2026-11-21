package main

import (
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Full authenticated generation/check pipeline with synthetic Responses transport.
// This verifies contracts and evidence, not semantic quality of a live model.
func TestCoachVocabularyGenerationAlternativeAndFailure(t *testing.T) {
	key := filepath.Join(t.TempDir(), "key")
	if err := os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PROVIDER_KEY_FILE", key)
	dir := t.TempDir()
	calls := 0
	fail := false
	cfg := &serverConfig{authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json")}
	cfg.httpClient = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		text := `{"models":[{"slug":"gpt-6.1-terra","visibility":"list"}]}`
		if !strings.Contains(r.URL.Path, "models") {
			calls++
			var wire map[string]any
			if err := json.NewDecoder(r.Body).Decode(&wire); err != nil {
				t.Fatal(err)
			}
			content := wire["input"].([]any)[0].(map[string]any)["content"].(string)
			if !strings.Contains(content, `"answer_language":"en"`) {
				t.Error("missing grounded direction", content)
			}
			if wire["text"].(map[string]any)["format"].(map[string]any)["name"] == "coach_assessment" {
				for _, want := range []string{`"target_text":"abholen"`, `"learner_answer":"  collect  "`, `"kind":"context_translation"`} {
					if !strings.Contains(content, want) {
						t.Error("missing evaluator context", want, content)
					}
				}
				if !strings.Contains(wire["instructions"].(string), "contextual synonyms") {
					t.Error("lost semantic assessment instruction")
				}
				if fail {
					return &http.Response{StatusCode: 503, Header: http.Header{}, Body: io.NopCloser(strings.NewReader("synthetic failure"))}, nil
				}
				text = accountTranslationSSE(`{"verdict":"correct","corrected_answer":"collect","explanation":"Collect is a valid contextual alternative to pick up.","uncertainty_reason":""}`, true, "response.completed")
			} else {
				text = accountTranslationSSE(vocabularyFixture, true, "response.completed")
			}
		}
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(text))}, nil
	})}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	token, session, err := cfg.auth.store.create("vocabulary-owner", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if err = cfg.provider.save(session.UserID, providerCredential{AccessToken: "synthetic", Expires: time.Now().Add(time.Hour)}); err != nil {
		t.Fatal(err)
	}
	history, err := openHistory(filepath.Join(dir, "users", sessionHash(session.UserID)+".json"))
	if err != nil {
		t.Fatal(err)
	}
	if err = history.append(translationRecord{ID: "original", translationInput: translationInput{SourceLanguage: "en", TargetLanguage: "de"}, translationResult: translationResult{Translation: "Ich muss das Paket abholen."}}); err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{"word-one", "word-two"} {
		body, _ := json.Marshal(coachInput{RequestID: id, Action: "practice", Locale: "en"})
		generated := authCall(h, "POST", "/v1/learning/coach", string(body), token)
		if generated.Code != 200 || !strings.Contains(generated.Body.String(), `"kind":"context_translation"`) {
			t.Fatal("generation", generated.Code, generated.Body.String())
		}
		check, _ := json.Marshal(coachInput{RequestID: "check-" + id, Action: "answer", TurnID: id, Text: "  collect  ", Locale: "en"})
		checked := authCall(h, "POST", "/v1/learning/coach", string(check), token)
		if checked.Code != 200 || !strings.Contains(checked.Body.String(), `"answer":"  collect  "`) {
			t.Fatal("exact answer lost", checked.Code, checked.Body.String())
		}
		if !fail && !strings.Contains(checked.Body.String(), `"verdict":"correct"`) {
			t.Fatal("contextual alternative rejected", checked.Body.String())
		}
		if fail && !strings.Contains(checked.Body.String(), `"assessment_state":"failed"`) {
			t.Fatal("provider failure became learner evidence", checked.Body.String())
		}
		before := calls
		replay := authCall(h, "POST", "/v1/learning/coach", string(check), token)
		if replay.Code != 200 || calls != before {
			t.Fatal("duplicate inference")
		}
		fail = true
	}
	value := authCall(h, "GET", "/v1/learning/coach", "", token)
	if !strings.Contains(value.Body.String(), `"correct":1`) || !strings.Contains(value.Body.String(), `"count":1`) {
		t.Fatal("failed attempt counted", value.Body.String())
	}
	if err = cfg.learningStore(session.UserID).transaction(func(d *learningData) error {
		if len(d.Profiles) != 0 {
			t.Fatal("exercise changed CEFR")
		}
		return nil
	}, false); err != nil {
		t.Fatal(err)
	}
}
