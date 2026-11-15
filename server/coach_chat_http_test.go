package main

import (
	"fmt"
	"os"
	"sync"
	"testing"
)

func TestCoachChatHTTPConcurrentOwnerAndStorage(t *testing.T) {
	f := newAssessmentFixture(t)
	// A free entry offer applies only when there is no unfinished exercise.
	if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error { d.Turns = nil; return nil }); e != nil {
		t.Fatal(e)
	}
	var wg sync.WaitGroup
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			w := f.call(coachInput{Action: "entry", RequestID: fmt.Sprintf("entry-%d", i), Locale: "ru"})
			if w.Code != 200 {
				t.Errorf("entry %d", w.Code)
			}
		}(i)
	}
	wg.Wait()
	if e := f.cfg.coachStore(f.owner).transaction(false, func(d *coachData) error {
		n := 0
		for _, v := range d.Turns {
			if v.Result != nil && v.Result.Kind == "nudge" {
				n++
			}
		}
		if n != 1 {
			t.Errorf("nudges=%d", n)
		}
		return nil
	}); e != nil {
		t.Fatal(e)
	}
	if f.calls.Load() != 0 {
		t.Fatal("entry inferred")
	}
	if w := f.call(coachInput{OwnerID: "foreign", Action: "entry", RequestID: "foreign", Locale: "en"}); w.Code != 409 {
		t.Fatal("owner fence", w.Code)
	}
	if w := f.call(coachInput{Action: "seen", TurnID: "one", Text: "old", RequestID: "seen", Locale: "en"}); w.Code != 409 {
		t.Fatal("stale seen", w.Code)
	}
	if e := os.Remove(f.cfg.coachStore(f.owner).lock.path); e != nil {
		t.Fatal(e)
	}
	if e := os.Mkdir(f.cfg.coachStore(f.owner).lock.path, 0700); e != nil {
		t.Fatal(e)
	}
	if w := f.call(coachInput{Action: "entry", RequestID: "storage", Locale: "en"}); w.Code != 503 {
		t.Fatal("storage must fail closed", w.Code)
	}
}
