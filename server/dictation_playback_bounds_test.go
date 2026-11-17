package main

import (
	"fmt"
	"testing"
)

func TestDictationPlaybackReservationBound(t *testing.T) {
	f := newPlaybackFixture(t)
	f.seed(t)
	if err := f.cfg.dictationTransaction(f.owner, true, func(d *dictationData) error {
		v := dictationFind(d, "one")
		for i := 0; i < 256; i++ {
			v.Playback.Listens = append(v.Playback.Listens, dictationListen{ID: fmt.Sprintf("old%d", i), Client: "tab", Step: 1, Done: true})
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	w := f.call("POST", "/one/playback", `{"id":"overflow","client":"tab","action":"start","step":1}`)
	if w.Code != 409 {
		t.Fatalf("unbounded reservation: %d %s", w.Code, w.Body)
	}
	// Idempotent old acknowledgements remain valid at capacity.
	w = f.call("POST", "/one/playback", `{"id":"old0","client":"tab","action":"start","step":1}`)
	if w.Code != 200 {
		t.Fatalf("retry at capacity: %d %s", w.Code, w.Body)
	}
}
