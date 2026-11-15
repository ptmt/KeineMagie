package main

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestCoachProgressRejectsInventedProseCounts(t *testing.T) {
	f := newAssessmentFixture(t)
	f.reply = func(*http.Request) (string, error) {
		return accountTranslationSSE(`{"message":"You completed ninety-nine perfect dictations."}`, true, "response.completed"), nil
	}
	if w := f.call(coachInput{Action: "progress", RequestID: "invented", Locale: "en"}); w.Code != 200 || strings.Contains(w.Body.String(), "ninety-nine") || !strings.Contains(w.Body.String(), `"state":"failed"`) {
		t.Fatalf("invented prose accepted: %d %s", w.Code, w.Body.String())
	}
}

func TestCoachProgressCountsRenderedFromServerInFiveLocales(t *testing.T) {
	for _, locale := range []string{"en", "de", "ru", "es", "fr"} {
		t.Run(locale, func(t *testing.T) {
			f := newAssessmentFixture(t)
			f.reply = func(*http.Request) (string, error) {
				return accountTranslationSSE(`{"next_step":"practice"}`, true, "response.completed"), nil
			}
			w := f.call(coachInput{Action: "progress", RequestID: "facts", Locale: locale})
			var wire struct {
				Turns []struct {
					ID      string `json:"id"`
					Message string `json:"message"`
				} `json:"turns"`
			}
			if e := json.Unmarshal(w.Body.Bytes(), &wire); e != nil {
				t.Fatal(e)
			}
			got := wire.Turns[len(wire.Turns)-1].Message
			want := coachProgressText(f.cfg.coachProgress(f.owner, f.cfg.auth.now().UTC()), locale, "practice")
			if w.Code != 200 || got != want || !strings.Contains(got, ": 1\n") {
				t.Fatalf("server facts mismatch: %d %q want %q", w.Code, got, want)
			}
		})
	}
}
