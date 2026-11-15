package main

import (
	"fmt"
	"testing"
	"time"
)

func TestCoachChatBoundsAndDuplicateAdmission(t *testing.T) {
	now := time.Now().UTC()
	in := coachInput{Action: "entry", RequestID: "one", Locale: "en"}
	d := coachData{}
	if err := coachChatMutation(&d, in, now); err != nil {
		t.Fatal(err)
	}
	if err := coachChatMutation(&d, in, now.Add(6*time.Hour)); err != nil {
		t.Fatal(err)
	}
	if len(d.Turns) != 1 || len(d.Receipts) != 1 || !d.LastVisit.Equal(now) {
		t.Fatal("replay changed admission")
	}
	d.Turns = make([]coachTurn, 250)
	if err := coachChatMutation(&d, coachInput{Action: "entry", RequestID: "full", Locale: "en"}, now.Add(6*time.Hour)); err != nil {
		t.Fatal(err)
	}
	if len(d.Turns) != 250 {
		t.Fatal("turn bound exceeded")
	}
	d.Receipts = make([]coachReceipt, 10000)
	if err := coachChatMutation(&d, coachInput{Action: "entry", RequestID: "quota", Locale: "en"}, now.Add(12*time.Hour)); err != errCoachConflict {
		t.Fatal("receipt limit exceeded")
	}
}

func TestCoachEntryFiveHourAdmission(t *testing.T) {
	now := time.Date(2026, 11, 15, 12, 0, 0, 0, time.UTC)
	d := coachData{}
	if err := coachChatMutation(&d, coachInput{Action: "entry", RequestID: "one", Locale: "ru"}, now); err != nil {
		t.Fatal(err)
	}
	if len(d.Turns) != 1 || d.Turns[0].Result.Kind != "nudge" {
		t.Fatal("first entry needs a free offer")
	}
	for _, delta := range []time.Duration{0, 5*time.Hour - time.Nanosecond} {
		if err := coachChatMutation(&d, coachInput{Action: "entry", RequestID: "retry" + delta.String(), Locale: "ru"}, now.Add(delta)); err != nil {
			t.Fatal(err)
		}
		if len(d.Turns) != 1 {
			t.Fatal("duplicate offer")
		}
	}
	if err := coachChatMutation(&d, coachInput{Action: "entry", RequestID: "boundary", Locale: "ru"}, now.Add(10*time.Hour-time.Nanosecond)); err != nil {
		t.Fatal(err)
	}
	if len(d.Turns) != 2 {
		t.Fatal("exact five hours since last visit must admit")
	}
}

func TestCoachDisclosureRejectsNonSourceAndPreservesGrading(t *testing.T) {
	now := time.Now().UTC()
	d := coachData{Turns: []coachTurn{{ID: "offer", State: "completed", Result: &coachResult{Kind: "nudge"}}}}
	if err := coachChatMutation(&d, coachInput{Action: "reveal", TurnID: "offer", Text: "source", RequestID: "invalid"}, now); err != errCoachConflict {
		t.Fatalf("source-free offer accepted: %v", err)
	}
	if len(d.Events) != 0 || len(d.Receipts) != 0 || d.Turns[0].Assisted {
		t.Fatal("invalid disclosure mutated state")
	}
	d.Turns[0].Result = &coachResult{Kind: "cloze", SourceID: "translation:original", Quote: "Original"}
	d.Turns[0].Attempt = &coachAttempt{ID: "answer", Outcome: "wrong", OriginalOutcome: "wrong", Assisted: false}
	for i := 0; i < 520; i++ {
		if err := coachChatMutation(&d, coachInput{Action: "reveal", TurnID: "offer", Text: "source", RequestID: fmt.Sprintf("r-%d", i)}, now); err != nil {
			t.Fatal(err)
		}
	}
	if len(d.Events) != 512 || d.Turns[0].SourceReveals != 520 {
		t.Fatal("disclosure bound/count")
	}
	if d.Turns[0].Assisted || d.Turns[0].Attempt.Assisted || d.Turns[0].Attempt.Outcome != "wrong" {
		t.Fatal("post-answer disclosure regraded evidence")
	}
	if err := coachChatMutation(&d, coachInput{Action: "seen", TurnID: "offer", Text: "offer:answer:future", RequestID: "spoof"}, now); err != errCoachConflict {
		t.Fatal("future seen accepted")
	}
}

func TestCoachRevealSeenAndBusy(t *testing.T) {
	now := time.Now().UTC()
	d := coachData{Turns: []coachTurn{{ID: "exercise", State: "completed", Result: &coachResult{Kind: "cloze", SourceID: "translation:original", Quote: "Original"}}}}
	in := coachInput{Action: "reveal", TurnID: "exercise", Text: "source", RequestID: "reveal"}
	if err := coachChatMutation(&d, in, now); err != nil {
		t.Fatal(err)
	}
	if !d.Turns[0].Assisted || d.Turns[0].SourceReveals != 1 || len(d.Events) != 1 {
		t.Fatal("missing assisted disclosure event")
	}
	if err := coachChatMutation(&d, in, now); err != nil {
		t.Fatal(err)
	}
	if d.Turns[0].SourceReveals != 1 {
		t.Fatal("replay counted twice")
	}
	d.Turns[0].Attempt = &coachAttempt{ID: "answer"}
	if err := coachChatMutation(&d, coachInput{Action: "seen", TurnID: "exercise", Text: "exercise:answer:", RequestID: "seen"}, now); err != nil {
		t.Fatal(err)
	}
	if d.Turns[0].SeenVersion != "exercise:answer:" {
		t.Fatal("seen receipt absent")
	}
	d.Turns = append(d.Turns, coachTurn{ID: "busy", State: "pending"})
	if err := coachChatMutation(&d, coachInput{Action: "entry", RequestID: "entry", Locale: "en"}, now); err != nil {
		t.Fatal(err)
	}
	if len(d.Turns) != 2 {
		t.Fatal("offer during pending work")
	}
}
