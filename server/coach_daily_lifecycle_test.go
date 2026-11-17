package main

import (
	"context"
	"fmt"
	"net/http"
	"testing"
	"time"
)

func TestDailyEntryRejectsNonExerciseResultWithoutRetry(t *testing.T) {
	f := dailyFixture(t)
	f.reply = func(*http.Request) (string, error) {
		return accountTranslationSSE(`{"message":"Have 30 seconds?","kind":"clarification","prompt":"","target":"grammar.case","source_id":"translation:original","quote":"Ich warte auf den Bus.","answers":[],"incorrect_answers":[],"explanation":"A clarification, not an exercise."}`, true, "response.completed"), nil
	}
	w := dailyCall(f, "first", "Europe/Berlin")
	if w.Code != 200 {
		t.Fatal(w.Code)
	}
	d := f.read(t)
	if d.Turns[0].State != "failed" {
		t.Fatal("daily entry accepted another offer", d.Turns[0])
	}
	if w = dailyCall(f, "second", "Europe/Berlin"); w.Code != 200 || f.calls.Load() != 1 {
		t.Fatal("automatic retry")
	}
}

func TestDailyEntryResumeMidnightDSTAndReplay(t *testing.T) {
	f := dailyFixture(t)
	now := time.Date(2026, 10, 24, 21, 59, 0, 0, time.UTC)
	f.cfg.auth.now = func() time.Time { return now }
	// Keep the fixture owner/source scope; extend only its synthetic session expiry.
	if e := f.cfg.auth.store.lock.locked(func() error {
		d, e := f.cfg.auth.store.read()
		if e != nil {
			return e
		}
		s := d.Sessions[sessionHash(f.token)]
		s.Expires = time.Now().AddDate(2, 0, 0)
		d.Sessions[sessionHash(f.token)] = s
		return f.cfg.auth.store.write(d)
	}); e != nil {
		t.Fatal(e)
	}
	for i, delta := range []time.Duration{0, 2 * time.Minute, 26 * time.Hour} {
		now = time.Date(2026, 10, 24, 21, 59, 0, 0, time.UTC).Add(delta)
		if w := dailyCall(f, fmt.Sprintf("day-%d", i), "Europe/Berlin"); w.Code != 200 {
			t.Fatal(w.Code, w.Body.String())
		}
		if f.calls.Load() != 1 {
			t.Fatal("unfinished exercise replaced", f.calls.Load())
		}
	}
	if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error { d.Turns[0].Attempt = &coachAttempt{Outcome: "correct"}; return nil }); e != nil {
		t.Fatal(e)
	}
	if w := dailyCall(f, "after-completion", "Europe/Berlin"); w.Code != 200 || f.calls.Load() != 1 {
		t.Fatal("resume did not bind day")
	}
	now = now.Add(24 * time.Hour)
	if w := dailyCall(f, "day-0", "Europe/Berlin"); w.Code != 200 || f.calls.Load() != 1 {
		t.Fatal("old request replay generated")
	}
	if w := dailyCall(f, "next-day", "Europe/Berlin"); w.Code != 200 || f.calls.Load() != 2 {
		t.Fatal("next local day", w.Code, w.Body.String(), f.calls.Load())
	}
}

func TestDailyEntryUncertainFailureDoesNotRetry(t *testing.T) {
	f := dailyFixture(t)
	f.reply = func(*http.Request) (string, error) { return "", context.DeadlineExceeded }
	for _, id := range []string{"one", "another-device", "relaunch"} {
		if w := dailyCall(f, id, "Europe/Berlin"); w.Code != 200 {
			t.Fatal(w.Code, w.Body.String())
		}
	}
	if f.calls.Load() != 1 {
		t.Fatal("uncertain acceptance repeated", f.calls.Load())
	}
}
