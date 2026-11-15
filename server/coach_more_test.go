package main

import (
	"encoding/json"
	"net/http"
	"path/filepath"
	"strings"
	"testing"
)

func TestCoachMoreUsesDifferentSavedContext(t *testing.T) {
	f := newAssessmentFixture(t)
	if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error {
		d.Turns[0].Attempt = &coachAttempt{Outcome: "correct", AssessmentState: "completed"}
		return nil
	}); e != nil {
		t.Fatal(e)
	}
	// Add an alternative exact owner source, without touching real history.
	ownerHistory, e := openHistory(filepath.Join(filepath.Dir(f.cfg.historyPath), "users", sessionHash(f.owner)+".json"))
	if e != nil {
		t.Fatal(e)
	}
	if e = ownerHistory.append(translationRecord{ID: "second", translationInput: translationInput{TargetLanguage: "de"}, translationResult: translationResult{Translation: "Wir fahren mit dem Zug."}}); e != nil {
		t.Fatal(e)
	}
	f.reply = func(r *http.Request) (string, error) {
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		content := body["input"].([]any)[0].(map[string]any)["content"].(string)
		var payload struct {
			Sources []coachSource `json:"sources"`
		}
		_ = json.Unmarshal([]byte(content), &payload)
		if len(payload.Sources) != 1 || payload.Sources[0].ID != "translation:second" {
			t.Fatal("reused context", payload.Sources)
		}
		return accountTranslationSSE(`{"message":"Try a different example.","kind":"cloze","prompt":"Wir fahren ___ dem Zug.","target":"verb_government.preposition_case","source_id":"translation:second","quote":"Wir fahren mit dem Zug.","answers":["mit"],"incorrect_answers":[],"explanation":"mit + Dativ"}`, true, "response.completed"), nil
	}
	in := coachInput{Action: "more", Text: "More", Locale: "en", RequestID: "another"}
	if w := f.call(in); w.Code != 200 || !strings.Contains(w.Body.String(), "Wir fahren") {
		t.Fatal(w.Code, w.Body.String())
	}
	if w := f.call(in); w.Code != 200 || f.calls.Load() != 1 {
		t.Fatal("duplicate more inferred")
	}
	if w := f.call(coachInput{Action: "more", Text: "More", Locale: "en", RequestID: "stale-more"}); w.Code != 409 || f.calls.Load() != 1 {
		t.Fatal("unfinished exercise replaced", w.Code)
	}
}
