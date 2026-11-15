package main

import (
	"testing"
	"time"
)

func TestCoachContextualActions(t *testing.T) {
	d := &coachData{}
	check := func(want ...string) {
		t.Helper()
		got := coachActions(d)
		if len(got) != len(want) {
			t.Fatalf("actions=%v want %v", got, want)
		}
		for i, a := range got {
			if a.Action != want[i] {
				t.Fatalf("actions=%v want %v", got, want)
			}
		}
	}
	check("practice")
	d.Turns = append(d.Turns, coachTurn{ID: "offer", State: "completed", Result: &coachResult{Kind: "nudge"}})
	check("practice")
	d.Turns = append(d.Turns, coachTurn{ID: "task", State: "completed", Result: &coachResult{Kind: "cloze", SourceID: "translation:one"}})
	check("reveal", "progress")
	// Opening after five hours must not offer a new task over an unfinished one.
	now := time.Now().UTC()
	old := now.Add(-6 * time.Hour)
	d.LastVisit = &old
	d.LastNudge = &old
	if e := coachChatMutation(d, coachInput{Action: "entry", RequestID: "return", Locale: "en"}, now); e != nil {
		t.Fatal(e)
	}
	if len(d.Turns) != 2 {
		t.Fatal("active exercise got another offer")
	}
	d.Turns[1].Attempt = &coachAttempt{Outcome: "correct", AssessmentState: "completed"}
	check("more", "progress")
	d.Turns[1].Attempt.Outcome = "wrong"
	check("explain", "more", "progress")
	d.Turns[1].Attempt.Outcome = "ambiguous"
	check("explain", "more", "progress")
	d.Turns[1].Attempt.AssessmentState = "failed"
	check("progress")
	d.Turns[1].Attempt.AssessmentState = "pending"
	check()
	d.Turns[1].Attempt = nil
	d.Turns[1].State = "failed"
	check("more", "progress")
	d.Turns[1].State = "completed"
	d.Turns[1].Result = &coachResult{Kind: "clarification"}
	check("more", "progress")
}
