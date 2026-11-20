package main

import (
	"fmt"
	"testing"
)

func TestManualPacingUpgradeRetainsOldStopAcknowledgement(t *testing.T) {
	f := newPlaybackFixture(t)
	f.seed(t)
	p := playbackDecode(t, f.call("POST", "/one/playback", playbackBody("old-admission", "client", "start", 0, 0)))
	body := fmt.Sprintf(`{"id":"old-stop","admission":"old-admission","client":"client","action":"stop","step":0,"fence":%d,"offset":0}`, p.Revision)
	p = playbackDecode(t, f.call("POST", "/one/playback", body))
	w := f.call("POST", "/one/pacing", fmt.Sprintf(`{"revision":0,"playback_revision":%d,"mutation_id":"upgrade","repeats":2,"gap_seconds":3}`, p.Revision))
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body)
	}
	p = playbackDecode(t, f.call("POST", "/one/playback", body))
	if p.WholeStarts != 1 || p.Cursor != 0 {
		t.Fatal("old ACK changed upgraded policy", p)
	}
}

func TestManualPacingLostAdmissionStopAndOwnerFence(t *testing.T) {
	f := newPlaybackFixture(t)
	f.seed(t)
	if w := f.call("POST", "/one/pacing", `{"revision":0,"playback_revision":0,"mutation_id":"upgrade","repeats":2,"gap_seconds":3}`); w.Code != 200 {
		t.Fatal(w.Code, w.Body)
	}
	// Pre-admission revision 1 survives a committed start with a lost ACK.
	p := playbackDecode(t, f.call("POST", "/one/playback", manualPlaybackBody("intro", "client", "start", 0, 0)))
	if w := f.call("POST", "/one/playback", manualPlaybackBody("intro", "foreign", "progress", 0, p.Active.Fence)); w.Code != 409 {
		t.Fatal("foreign owner fence", w.Code)
	}
	if w := f.call("POST", "/one/playback", playbackBody("old-client", "old", "start", 0, 0)); w.Code != 409 {
		t.Fatal("old client drove v2", w.Code)
	}
	body := `{"policy_version":2,"id":"stop","admission":"intro","client":"client","action":"stop","step":0,"fence":1,"offset":0}`
	p = playbackDecode(t, f.call("POST", "/one/playback", body))
	p = playbackDecode(t, f.call("POST", "/one/playback", body))
	if p.WholeStarts != 1 || p.Cursor != 0 || p.Active != nil || len(p.Stops) != 1 || !p.Listens[0].Stopped || p.Listens[0].Ended {
		t.Fatalf("Stop corrupted evidence: %+v", p)
	}
	if w := f.call("POST", "/one/playback", manualPlaybackBody("intro", "client", "ended", 0, p.Listens[0].Fence)); w.Code != 409 {
		t.Fatal("stale ending accepted", w.Code)
	}
	// Stop during a writing gap resets the cursor, not the start allowance.
	p = playbackDecode(t, f.call("POST", "/one/playback", manualPlaybackBody("again", "client", "start", 0, 0)))
	p = playbackDecode(t, f.call("POST", "/one/playback", manualPlaybackBody("again", "client", "ended", 0, p.Active.Fence)))
	p = playbackDecode(t, f.call("POST", "/one/playback", fmt.Sprintf(`{"policy_version":2,"id":"gap-stop","client":"client","action":"stop","step":0,"fence":%d,"offset":0}`, p.Revision)))
	if p.Cursor != 0 || p.WholeStarts != 2 || !p.Listens[1].Ended {
		t.Fatal(p)
	}
}
