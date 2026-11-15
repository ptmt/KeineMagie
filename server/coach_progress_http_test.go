package main

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestCoachProgressExplicitRouteOneCall(t *testing.T) {
	f := newAssessmentFixture(t)
	f.reply = func(r *http.Request) (string, error) {
		var body map[string]any
		if e := json.NewDecoder(r.Body).Decode(&body); e != nil {
			t.Fatal(e)
		}
		content := body["input"].([]any)[0].(map[string]any)["content"].(string)
		for _, want := range []string{"translations", "vocabulary_statuses", "saved_podcast_passages", "dictation_checks", "unavailable", "last_30_days"} {
			if !strings.Contains(content, want) {
				t.Fatal("missing coverage", want)
			}
		}
		if strings.Contains(content, "assessment-owner") || strings.Contains(content, "Ich warte") {
			t.Fatal("raw content included in aggregate")
		}
		return accountTranslationSSE(`{"next_step":"practice"}`, true, "response.completed"), nil
	}
	in := coachInput{Action: "progress", Text: "My progress", RequestID: "progress-one", Locale: "en", OwnerID: f.owner}
	if w := f.call(in); w.Code != 200 || !strings.Contains(w.Body.String(), "Retained activity") {
		t.Fatal(w.Code, w.Body.String())
	}
	if w := f.call(in); w.Code != 200 || f.calls.Load() != 1 {
		t.Fatal("duplicate inferred", w.Code, f.calls.Load())
	}
	// Legacy explicit text routes to the same bounded progress operation without rewriting its receipt identity.
	legacy := coachInput{Action: "message", Text: "Фидбек", RequestID: "legacy-progress", Locale: "ru"}
	if w := f.call(legacy); w.Code != 200 {
		t.Fatal(w.Code)
	}
	if w := f.call(legacy); w.Code != 200 || f.calls.Load() != 2 {
		t.Fatal("legacy replay inferred", w.Code)
	}
	if w := f.call(coachInput{Action: "entry", RequestID: "entry-two", Locale: "en"}); w.Code != 200 || f.calls.Load() != 2 {
		t.Fatal("entry inferred")
	}
}
