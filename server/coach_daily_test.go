package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

func dailyCall(f *assessmentFixture, id, zone string) *httptest.ResponseRecorder {
	b, _ := json.Marshal(map[string]string{"action": "entry", "request_id": id, "locale": "en", "owner_id": f.owner, "time_zone": zone})
	r := httptest.NewRequest("POST", "/v1/learning/coach", strings.NewReader(string(b)))
	r.Header.Set("Authorization", "Bearer "+f.token)
	w := httptest.NewRecorder()
	f.h.ServeHTTP(w, r)
	return w
}
func dailyFixture(t *testing.T) *assessmentFixture {
	f := newAssessmentFixture(t)
	if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error { d.Turns = nil; return nil }); e != nil {
		t.Fatal(e)
	}
	f.reply = func(*http.Request) (string, error) {
		return accountTranslationSSE(`{"message":"A short exercise.","kind":"cloze","prompt":"Ich warte ___ den Bus.","target":"verb_government.preposition_case","source_id":"translation:original","quote":"Ich warte auf den Bus.","answers":["auf"],"incorrect_answers":[],"explanation":"warten auf"}`, true, "response.completed"), nil
	}
	return f
}
func TestDailyEntryConcurrentOneDurableExercise(t *testing.T) {
	f := dailyFixture(t)
	var wg sync.WaitGroup
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			w := dailyCall(f, fmt.Sprintf("device-%d", i), "Europe/Berlin")
			if w.Code != 200 {
				t.Errorf("entry: %d %s", w.Code, w.Body.String())
			}
		}(i)
	}
	wg.Wait()
	if f.calls.Load() != 1 {
		t.Fatalf("accepted provider requests=%d want exactly 1", f.calls.Load())
	}
	d := f.read(t)
	if len(d.Turns) != 1 || d.Turns[0].State != "completed" || d.Turns[0].Result.Kind != "cloze" {
		t.Fatalf("not one real exercise: %+v", d.Turns)
	}
	// New handler and store instances must reuse disk, not an in-memory gate.
	var e error
	f.h, e = newHandler(f.cfg)
	if e != nil {
		t.Fatal(e)
	}
	if w := dailyCall(f, "relaunch", "America/New_York"); w.Code != 200 || f.calls.Load() != 1 {
		t.Fatalf("relaunch/time-zone bypass: %d calls=%d", w.Code, f.calls.Load())
	}
}
