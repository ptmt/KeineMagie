package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestCoachProgressOwnerCoverage(t *testing.T) {
	f := newAssessmentFixture(t)
	now := time.Now().UTC()
	if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error {
		d.Turns[0].Attempt = &coachAttempt{ID: "a", Outcome: "wrong", At: now, AssessmentState: "completed"}
		return nil
	}); e != nil {
		t.Fatal(e)
	}
	if e := f.cfg.learningStore(f.owner).transaction(func(d *learningData) error {
		d.Vocabulary = append(d.Vocabulary, learningVocabulary{Status: "known", UpdatedAt: now})
		return nil
	}, true); e != nil {
		t.Fatal(e)
	}
	p := f.cfg.coachProgress(f.owner, now)
	if p.Translations.Count != 1 || p.Coach.Count != 1 || p.Vocabulary.Count != 1 || p.Dictation.Status != "unavailable" {
		t.Fatalf("coverage=%+v", p)
	}
	path := filepath.Join(filepath.Dir(f.cfg.historyPath), "dictations", sessionHash(f.owner), "history.json")
	if e := learningAtomicJSON(path, map[string]any{"items": []any{map[string]any{"checked": true, "created": now.Format(time.RFC3339), "assisted": true, "differences": []any{map[string]string{"kind": "missing"}}}}}); e != nil {
		t.Fatal(e)
	}
	p = f.cfg.coachProgress(f.owner, now)
	if p.Dictation.Count != 1 || p.Dictation.Assisted != 1 || p.Dictation.Differences != 1 {
		t.Fatalf("dictation=%+v", p.Dictation)
	}
	other := f.cfg.coachProgress("other", now)
	if other.Coach.Count != 0 || other.Vocabulary.Count != 0 || other.Dictation.Status != "unavailable" {
		t.Fatal("owner leak")
	}
	if e := os.WriteFile(path, []byte(`{"items":`), 0600); e != nil {
		t.Fatal(e)
	}
	p = f.cfg.coachProgress(f.owner, now)
	if p.Dictation.Status != "unavailable" {
		t.Fatal("corrupt dataset must not be zero")
	}
	b, _ := json.Marshal(p)
	var wire map[string]json.RawMessage
	_ = json.Unmarshal(b, &wire)
	var unavailable map[string]any
	_ = json.Unmarshal(wire["dictation_checks"], &unavailable)
	if _, ok := unavailable["count"]; ok {
		t.Fatal("unavailable encoded as zero")
	}
}
