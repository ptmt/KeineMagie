package main

import (
	"encoding/json"
	"fmt"
	"reflect"
	"testing"
)

func TestManualPacingUpgradeAndSettings(t *testing.T) {
	f := newPlaybackFixture(t)
	f.seed(t)
	if e := f.cfg.dictationTransaction(f.owner, true, func(d *dictationData) error {
		v := dictationFind(d, "one")
		v.Draft = "Keep my draft"
		v.Playback.WholeStarts = 3
		return nil
	}); e != nil {
		t.Fatal(e)
	}
	body := `{"revision":0,"playback_revision":0,"mutation_id":"upgrade","repeats":3,"gap_seconds":8}`
	w := f.call("POST", "/one/pacing", body)
	if w.Code != 200 {
		t.Fatalf("upgrade: %d %s", w.Code, w.Body)
	}
	var v dictationRecord
	json.Unmarshal(w.Body.Bytes(), &v)
	if v.PlaybackPolicyVersion != 2 || v.Draft != "Keep my draft" || v.Playback.WholeStarts != 3 || v.Mode != "whole" {
		t.Fatalf("destructive upgrade: %+v", v)
	}
	if len(v.Ready) == 0 || v.Playback.Cursor != 0 {
		t.Fatal(v)
	}
	if w = f.call("POST", "/one/pacing", body); w.Code != 200 {
		t.Fatal("lost ACK retry", w.Code, w.Body)
	}
	w = f.call("PUT", "/one", fmt.Sprintf(`{"revision":%d,"mode":"sentences","step":0,"draft":"Keep typing","replays":0}`, v.Revision))
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body)
	}
	json.Unmarshal(w.Body.Bytes(), &v)
	var raw map[string]any
	json.Unmarshal(w.Body.Bytes(), &raw)
	if raw["pacing"].(map[string]any)["repeats"] != float64(3) {
		t.Fatal(raw)
	}
	if _, ok := raw["pacing_history"]; ok {
		t.Fatal("private old source plan exposed")
	}
	p := playbackDecode(t, f.call("POST", "/one/playback", manualPlaybackBody("intro", "client", "start", 0, 0)))
	if p.WholeStarts != 4 {
		t.Fatal(p)
	}
	p = playbackDecode(t, f.call("POST", "/one/playback", manualPlaybackBody("intro", "client", "ended", 0, p.Active.Fence)))
	if p.Cursor != 1 {
		t.Fatalf("intro cursor: %+v", p)
	}
	w = f.call("POST", "/one/pacing", fmt.Sprintf(`{"revision":%d,"playback_revision":%d,"mutation_id":"change","repeats":2,"gap_seconds":3}`, v.Revision, p.Revision))
	if w.Code != 409 {
		t.Fatal("settings after start must conflict", w.Code)
	}
}
func manualPlaybackBody(id, client, action string, step, fence int) string {
	return `{"policy_version":2,` + playbackBody(id, client, action, step, fence)[1:]
}
func TestManualPacingConservativeFragments(t *testing.T) {
	for _, tc := range []struct {
		input string
		want  []string
	}{
		{"Er sagt: „Dr. Müller zahlt 3.50 Euro.“ Danach gehen wir heim.", []string{"Er sagt: „Dr. Müller zahlt 3.50 Euro.“", "Danach gehen wir heim."}},
		{"Prof. A. Müller erklärt z.B. diesen Satz. Danach endet die Stunde.", []string{"Prof. A. Müller erklärt z.B. diesen Satz.", "Danach endet die Stunde."}},
		{"Dr. Müller zahlt 3,50 Euro, weil die Ware heute günstig ist.", []string{"Dr. Müller zahlt 3,50 Euro,", "weil die Ware heute günstig ist."}},
		{"Wir kaufen Äpfel, Birnen, Brot und Milch.", []string{"Wir kaufen Äpfel, Birnen, Brot und Milch."}},
		{"Er sagt: „Wir bleiben hier, weil der Regen nicht aufhört.“", []string{"Er sagt: „Wir bleiben hier, weil der Regen nicht aufhört.“"}},
		{"Das ist z. B. eine Zahl von 3.14. Morgen geht es weiter.", []string{"Das ist z. B. eine Zahl von 3.14.", "Morgen geht es weiter."}},
	} {
		if got := dictationFragments(tc.input); !reflect.DeepEqual(got, tc.want) {
			t.Errorf("%q: %#v want %#v", tc.input, got, tc.want)
		}
	}
}
