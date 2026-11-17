package main

import (
	"strings"
	"testing"
	"time"
)

func TestDailyOptInMigratesLegacyOffersWithoutDeletingData(t *testing.T) {
	f := dailyFixture(t)
	if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error {
		d.Turns = []coachTurn{{ID: "old-offer", State: "completed", At: time.Now().Add(-48 * time.Hour), Result: &coachResult{Kind: "nudge", Message: "Have 30 seconds?"}}}
		return nil
	}); e != nil {
		t.Fatal(e)
	}
	w := dailyCall(f, "daily", "Europe/Berlin")
	if w.Code != 200 || strings.Contains(w.Body.String(), "Have 30 seconds?") {
		t.Fatal("legacy offer still displayed", w.Code, w.Body.String())
	}
	if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error { d.Turns[1].Attempt = &coachAttempt{Outcome: "correct"}; return nil }); e != nil {
		t.Fatal(e)
	}
	w = f.call(coachInput{Action: "entry", RequestID: "released-client", Locale: "en"})
	if w.Code != 200 || strings.Contains(w.Body.String(), "Have 30 seconds?") {
		t.Fatal("old client created duplicate offer", w.Code, w.Body.String())
	}
	d := f.read(t)
	if len(d.Turns) != 2 || d.Turns[0].ID != "old-offer" || d.Turns[0].Result.Message != "Have 30 seconds?" {
		t.Fatal("migration deleted history or appended offer", d.Turns)
	}
	if f.calls.Load() != 1 {
		t.Fatal("legacy entry spent quota")
	}
}
