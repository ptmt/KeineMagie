package main

import (
	"encoding/json"
	"fmt"
	"testing"
)

func TestManualPacingExtraReplayEvidence(t *testing.T) {
	f := newPlaybackFixture(t)
	f.seed(t)
	if w := f.call("POST", "/one/pacing", `{"revision":0,"playback_revision":0,"mutation_id":"upgrade","repeats":2,"gap_seconds":3}`); w.Code != 200 {
		t.Fatal(w.Code, w.Body)
	}
	if w := f.call("PUT", "/one", `{"revision":1,"mode":"sentences","step":0,"draft":"","replays":0}`); w.Code != 200 {
		t.Fatal(w.Code, w.Body)
	}
	for step := 0; step < 3; step++ {
		id := fmt.Sprintf("planned-%d", step)
		p := playbackDecode(t, f.call("POST", "/one/playback", manualPlaybackBody(id, "client", "start", step, 0)))
		playbackDecode(t, f.call("POST", "/one/playback", manualPlaybackBody(id, "client", "ended", step, p.Active.Fence)))
	}
	body := `{"policy_version":2,"id":"extra","client":"client","action":"start","step":1,"intent":"extra","offset":0}`
	w := f.call("POST", "/one/playback", body)
	if w.Code != 200 {
		t.Fatalf("explicit extra replay: %d %s", w.Code, w.Body)
	}
	p := playbackDecode(t, w)
	before := len(p.Listens)
	p = playbackDecode(t, f.call("POST", "/one/playback", body))
	if len(p.Listens) != before {
		t.Fatal("duplicate replay counted")
	}
	p = playbackDecode(t, f.call("POST", "/one/playback", manualPlaybackBody("extra", "client", "ended", 1, p.Active.Fence)))
	if p.Cursor != 3 {
		t.Fatal("extra replay advanced plan", p)
	}
	var raw map[string]any
	b, _ := json.Marshal(p.Listens[len(p.Listens)-1])
	json.Unmarshal(b, &raw)
	if raw["intent"] != "extra" || raw["ended"] != true || raw["asset"] != float64(1) || raw["policy_version"] != float64(2) {
		t.Fatal(raw)
	}
}
