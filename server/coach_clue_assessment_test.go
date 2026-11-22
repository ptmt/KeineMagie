package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
)

func TestCoachVocabularyGenerationRejectsMissingClueWithoutRetry(t *testing.T) {
	calls := 0
	payload := `{"message":"Insert a suitable noun.","kind":"cloze","prompt":"Ich mache ein ___ bei euch.","target":"vocabulary.word_choice","source_id":"translation:fixture","quote":"Ich mache ein Praktikum bei euch.","answers":["Praktikum"],"incorrect_answers":[],"explanation":"Synthetic explanation."}`
	p := &providerService{client: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		calls++
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(accountTranslationSSE(payload, true, "response.completed")))}, nil
	})}}
	_, err := p.coachGenerate(context.Background(), "synthetic", []coachSource{{ID: "translation:fixture", Language: "de", Text: "Ich mache ein Praktikum bei euch."}}, nil, coachInput{Action: "practice", Locale: "en"})
	if err == nil || calls != 1 {
		t.Fatal("missing clue accepted or hidden retry", err, calls)
	}
}

func TestCoachClueAssessmentUsesVisibleMeaningNotHiddenAnswer(t *testing.T) {
	for _, verdict := range []string{"correct", "uncertain"} {
		t.Run(verdict, func(t *testing.T) {
			calls := 0
			p := &providerService{client: &http.Client{Transport: transportFunc(func(req *http.Request) (*http.Response, error) {
				calls++
				var wire map[string]any
				json.NewDecoder(req.Body).Decode(&wire)
				instructions := wire["instructions"].(string)
				if !strings.Contains(instructions, "visible clue") || !strings.Contains(instructions, "hidden source word") {
					t.Error("missing ambiguity grading contract")
				}
				content := wire["input"].([]any)[0].(map[string]any)["content"].(string)
				if !strings.Contains(content, `"clue":"a period of practical work experience"`) || !strings.Contains(content, `"learner_answer":"  Traineeship  "`) {
					t.Error("lost exact clue or answer", content)
				}
				if strings.Contains(content, `"answers"`) {
					t.Error("hidden answer list leaked into grading")
				}
				reason := ""
				if verdict == "uncertain" {
					reason = "ambiguous_exercise"
				}
				b, _ := json.Marshal(map[string]string{"verdict": verdict, "corrected_answer": "Traineeship", "explanation": "Synthetic contextual assessment.", "uncertainty_reason": reason})
				return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(accountTranslationSSE(string(b), true, "response.completed")))}, nil
			})}}
			turn := coachTurn{Language: "de", Result: &coachResult{Kind: "cloze", Prompt: "Ich mache ein ___ bei euch.", Clue: "a period of practical work experience", ClueKind: "gloss", ClueLanguage: "en", Answers: []string{"Praktikum"}}, Attempt: &coachAttempt{Answer: "  Traineeship  "}}
			got, e := p.coachAssessGenerate(context.Background(), "synthetic", coachSource{ID: "translation:fixture", Language: "de", Text: "Ich mache ein Praktikum bei euch."}, turn, "en")
			if e != nil || got.Verdict != verdict || calls != 1 {
				t.Fatal(got, e, calls)
			}
		})
	}
}
