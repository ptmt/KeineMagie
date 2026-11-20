package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestManualPacingThreeRepeatsAtAcceptedFragmentBound(t *testing.T) {
	f := newPlaybackFixture(t)
	body, _ := json.Marshal(map[string]any{"id": "many", "title": "Test", "language": "de", "text": strings.Repeat("Das stimmt. ", 59), "playback_policy_version": 2})
	if w := f.call("POST", "", string(body)); w.Code != 200 {
		t.Fatal(w.Code, w.Body)
	}
	w := f.call("POST", "/many/pacing", `{"revision":0,"playback_revision":0,"mutation_id":"three","repeats":3,"gap_seconds":3}`)
	if w.Code != 200 {
		t.Fatal("every accepted fragment plan supports three repeats", w.Code, w.Body)
	}
	var v dictationRecord
	json.Unmarshal(w.Body.Bytes(), &v)
	if len(v.Plan) != 179 {
		t.Fatal(len(v.Plan))
	}
}

func TestManualPacingCreation(t *testing.T) {
	f := newPlaybackFixture(t)
	w := f.call("POST", "", `{"id":"manual","title":"Test","text":"Heute bleiben wir zu Hause, weil es draußen sehr stark regnet. Morgen gehen wir spazieren.","language":"de","playback_policy_version":2}`)
	if w.Code != 200 {
		t.Fatalf("policy 2 creation: %d %s", w.Code, w.Body)
	}
	var v dictationRecord
	if e := json.Unmarshal(w.Body.Bytes(), &v); e != nil {
		t.Fatal(e)
	}
	if v.Mode != "sentences" || v.Playback.Cursor != 0 {
		t.Fatalf("must default to explicit whole introduction: %+v", v)
	}
	if len(v.Plan) != 8 {
		t.Fatalf("intro, three fragments each twice, final: %+v", v.Plan)
	}
	for i := 1; i < 7; i += 2 {
		if v.Plan[i].Asset != v.Plan[i+1].Asset {
			t.Fatalf("repeat must reuse audio: %+v", v.Plan)
		}
	}
	if v.Plan[0].Kind != "whole" || v.Plan[7].Kind != "final" {
		t.Fatal(v.Plan)
	}
	if len(v.Ready) != 0 {
		t.Fatal("creation must not prepare audio")
	}
}
