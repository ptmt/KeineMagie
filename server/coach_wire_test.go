package main

import (
	"encoding/json"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

// Go handler serialization feeds the actual Swift DTO decoder in test_coach_wire.py.
// No private history, credentials, or live provider is involved.
func TestCoachWireExport(t *testing.T) {
	dir := os.Getenv("KM_COACH_WIRE_DIR")
	if dir == "" {
		t.Skip("cross-language runner not active")
	}
	f := newAssessmentFixture(t)
	var original coachData
	if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error { original = *d; *d = coachData{}; return nil }); e != nil {
		t.Fatal(e)
	}
	save := func(name string) {
		r := httptest.NewRequest("GET", "/v1/learning/coach", nil)
		r.Header.Set("Authorization", "Bearer "+f.token)
		w := httptest.NewRecorder()
		f.h.ServeHTTP(w, r)
		if w.Code != 200 {
			t.Fatal(w.Code)
		}
		var value map[string]json.RawMessage
		if e := json.Unmarshal(w.Body.Bytes(), &value); e != nil {
			t.Fatal(e)
		}
		for _, key := range []string{"turns", "observations"} {
			if string(value[key]) == "null" || value[key] == nil {
				t.Fatal("null Coach array", key)
			}
		}
		if e := os.WriteFile(filepath.Join(dir, name+".json"), w.Body.Bytes(), 0600); e != nil {
			t.Fatal(e)
		}
	}
	save("initial")
	if w := f.call(coachInput{Action: "entry", RequestID: "offer", Locale: "ru"}); w.Code != 200 {
		t.Fatal(w.Code)
	}
	save("offer")
	if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error { *d = original; return nil }); e != nil {
		t.Fatal(e)
	}
	save("exercise")
	if w := f.call(answerInput()); w.Code != 200 {
		t.Fatal(w.Code)
	}
	save("assessment")
	if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error {
		a := coachFind(d, "one").Attempt
		a.Assessment = nil
		a.AssessmentState = "pending"
		a.Outcome = "ambiguous"
		return nil
	}); e != nil {
		t.Fatal(e)
	}
	save("pending")
	if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error { coachFind(d, "one").Attempt.AssessmentState = "failed"; return nil }); e != nil {
		t.Fatal(e)
	}
	save("failed")
	if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error { coachFind(d, "one").Attempt.AssessmentState = ""; return nil }); e != nil {
		t.Fatal(e)
	}
	save("legacy")
	if w := f.call(coachInput{RequestID: "reset", Action: "reset", Locale: "en"}); w.Code != 200 {
		t.Fatal(w.Code)
	}
	save("reset")
	if f.calls.Load() != 1 {
		t.Fatal("GET inferred")
	}
}
