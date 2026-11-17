package main

import (
	"testing"
)

// Explicitly moving on must not make an old failed assessment a permanent
// automatic-entry blocker. Pending work still needs explicit cancellation.
func TestDailyEntryHistoricalAssessmentDoesNotBlockNewPractice(t *testing.T) {
	for _, state := range []string{"failed", "canceled", "unknown"} {
		t.Run(state, func(t *testing.T) {
			f := dailyFixture(t)
			f.addTurn(t, "old")
			if err := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error {
				d.Turns[0].Attempt = &coachAttempt{ID: "old-answer", Answer: "auf", AssessmentState: state}
				return nil
			}); err != nil {
				t.Fatal(err)
			}
			// The user explicitly continues through the existing public API.
			if w := f.call(coachInput{Action: "practice", RequestID: "explicit-new", Locale: "en"}); w.Code != 200 {
				t.Fatal(w.Code, w.Body.String())
			}
			if w := f.call(coachInput{Action: "skip", TurnID: "explicit-new", RequestID: "skip-new", Locale: "en"}); w.Code != 200 {
				t.Fatal(w.Code, w.Body.String())
			}
			if w := dailyCall(f, "fresh-day", "Europe/Berlin"); w.Code != 200 {
				t.Fatal(w.Code, w.Body.String())
			}
			if f.calls.Load() != 2 {
				t.Fatalf("historical %s assessment blocked daily generation after explicit new exercise: calls=%d", state, f.calls.Load())
			}
			d := f.read(t)
			if d.Turns[0].Attempt.AssessmentState != state || d.Turns[0].Attempt.Answer != "auf" {
				t.Fatal("historical answer was changed")
			}
		})
	}
}
