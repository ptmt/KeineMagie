package main

import (
	"encoding/json"
	"testing"
)

func TestNewDictationDefaultsToThreeWithoutMigratingSavedPacing(t *testing.T) {
	f := newPlaybackFixture(t)
	decode := func(method, path, body string) dictationRecord {
		t.Helper()
		w := f.call(method, path, body)
		if w.Code != 200 {
			t.Fatalf("%s %s: %d %s", method, path, w.Code, w.Body)
		}
		var v dictationRecord
		if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
			t.Fatal(err)
		}
		return v
	}
	v := decode("POST", "", `{"id":"defaults","title":"Defaults","text":"Hallo Welt.","language":"de","playback_policy_version":2}`)
	if v.Pacing == nil || v.Pacing.Repeats != 3 || v.Pacing.GapSeconds != 3 || len(v.Plan) != 5 {
		t.Fatalf("new attempt must have intro + three readings + final, unchanged gap: %+v", v)
	}
	v = decode("POST", "/defaults/pacing", `{"revision":0,"playback_revision":0,"mutation_id":"explicit-two","repeats":2,"gap_seconds":8}`)
	v = decode("GET", "/defaults", "")
	if v.Pacing.Repeats != 2 || v.Pacing.GapSeconds != 8 || len(v.Plan) != 4 {
		t.Fatalf("saved explicit pacing changed: %+v", v)
	}
	next := decode("POST", "/defaults/attempts", `{"id":"defaults-next","playback_policy_version":2}`)
	if next.Pacing == nil || next.Pacing.Repeats != 3 || next.Pacing.GapSeconds != 3 || len(next.Plan) != 5 {
		t.Fatalf("new attempt default: %+v", next)
	}
	v = decode("GET", "/defaults", "")
	if v.Pacing.Repeats != 2 || v.Pacing.GapSeconds != 8 {
		t.Fatal("new attempt migrated source")
	}
	legacy := decode("POST", "", `{"id":"legacy-default","title":"Legacy","text":"Hallo Welt.","language":"de","playback_policy_version":1}`)
	legacy = decode("GET", "/legacy-default", "")
	if legacy.PlaybackPolicyVersion != 1 || legacy.Pacing != nil {
		t.Fatal("legacy silently upgraded")
	}
}
