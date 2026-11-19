package main

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestDictationStopAuthorizationAndCanceledAdmission(t *testing.T) {
	f := newPlaybackFixture(t)
	f.seed(t)
	request := func(action, expected string, browser, csrf, canceled bool) int {
		r := httptest.NewRequest("POST", "/v1/learning/dictations/one/playback", strings.NewReader(playbackBody("operation", "native", action, 0, 0)))
		if browser {
			r.AddCookie(&http.Cookie{Name: browserCookie, Value: f.browser})
			r.Header.Set("Origin", "https://example.com")
			if csrf {
				r.Header.Set("X-CSRF-Token", browserCSRF(f.browser))
			}
		} else {
			r.Header.Set("Authorization", "Bearer "+f.token)
		}
		r.Header.Set("X-Dictation-Owner", expected)
		if canceled {
			ctx, cancel := context.WithCancel(r.Context())
			cancel()
			r = r.WithContext(ctx)
		}
		w := httptest.NewRecorder()
		f.h.ServeHTTP(w, r)
		return w.Code
	}
	if code := request("stop", "wrong-owner", false, false, false); code != 403 {
		t.Fatal("expected owner bypass", code)
	}
	if code := request("stop", f.owner, true, false, false); code != 403 {
		t.Fatal("CSRF bypass", code)
	}
	if code := request("start", f.owner, false, false, true); code == 200 {
		t.Fatal("canceled admission accepted")
	}
	f.cfg.dictationTransaction(f.owner, false, func(d *dictationData) error {
		p := dictationFind(d, "one").Playback
		if p.Revision != 0 || p.WholeStarts != 0 || p.Active != nil {
			t.Errorf("unauthorized/canceled mutation: %+v", p)
		}
		return nil
	})
	if code := request("stop", f.owner, false, false, false); code != 200 {
		t.Fatal("valid native stop", code)
	}
}

func TestDictationStopBeforeDelayedAdmission(t *testing.T) {
	f := newPlaybackFixture(t)
	f.seed(t)
	p := playbackDecode(t, f.call("POST", "/one/playback", `{"id":"stop","client":"native","action":"stop","step":0,"fence":0,"admission":"late"}`))
	if p.WholeStarts != 0 {
		t.Fatal(p)
	}
	if w := f.call("POST", "/one/playback", playbackBody("late", "native", "start", 0, 0)); w.Code != 409 {
		t.Fatal("late start admitted", w.Code)
	}
}

func TestDictationStopRetainsFinalOnceAndDurableReceipt(t *testing.T) {
	f := newPlaybackFixture(t)
	f.seed(t)
	var count int
	f.cfg.dictationTransaction(f.owner, false, func(d *dictationData) error { count = len(dictationFind(d, "one").Plan); return nil })
	p := dictationPlayback{Cursor: 1}
	runSentences := func(prefix string) {
		for step := 1; step < count-1; step++ {
			id := fmt.Sprintf("%s%d", prefix, step)
			p = playbackDecode(t, f.call("POST", "/one/playback", playbackBody(id, "native", "start", step, 0)))
			p = playbackDecode(t, f.call("POST", "/one/playback", playbackBody(id, "native", "ended", step, p.Active.Fence)))
		}
	}
	runSentences("first")
	p = playbackDecode(t, f.call("POST", "/one/playback", playbackBody("final", "native", "start", count-1, 0)))
	body := playbackBody("stop-final", "native", "stop", 0, p.Revision)
	p = playbackDecode(t, f.call("POST", "/one/playback", body))
	if !p.FinalUsed || p.WholeStarts != 1 || p.Cursor != 1 || p.Listens[len(p.Listens)-1].Done || !p.Listens[len(p.Listens)-1].Stopped {
		t.Fatal("stop misreported completion/refunded final", p)
	}
	revision := p.Revision
	var err error
	f.h, err = newHandler(f.cfg)
	if err != nil {
		t.Fatal(err)
	}
	p = playbackDecode(t, f.call("POST", "/one/playback", body))
	if p.Revision != revision {
		t.Fatal("receipt lost on store reopen")
	}
	runSentences("again")
	if w := f.call("POST", "/one/playback", playbackBody("final-again", "native", "start", count-1, 0)); w.Code != 409 {
		t.Fatal("final replay bypass", w.Code)
	}
	f.cfg.dictationTransaction(f.owner, false, func(d *dictationData) error {
		if d.Generations != 120 || d.Day != "2000-01-01" || dictationFind(d, "one").Revision != 0 {
			t.Error("stop altered quota or draft revision")
		}
		return nil
	})
}

func TestDictationExplicitStop(t *testing.T) {
	f := newPlaybackFixture(t)
	f.seed(t)
	call := func(id, action string, step, fence int) dictationPlayback {
		t.Helper()
		return playbackDecode(t, f.call("POST", "/one/playback", playbackBody(id, "native", action, step, fence)))
	}
	for n := 1; n <= 4; n++ {
		p := call(fmt.Sprint("listen", n), "start", 0, 0)
		p = call(p.Active.ID, "progress", 0, p.Active.Fence)
		stopBody := playbackBody(fmt.Sprint("stop", n), "native", "stop", 0, p.Revision)
		p = playbackDecode(t, f.call("POST", "/one/playback", stopBody))
		if p.Active != nil || p.WholeStarts != n || p.Cursor != 1 {
			t.Fatalf("stop refunded/failed reset: %+v", p)
		}
		revision := p.Revision
		p = playbackDecode(t, f.call("POST", "/one/playback", stopBody))
		if p.Revision != revision {
			t.Fatal("stop retry not idempotent")
		}
	}
	if w := f.call("POST", "/one/playback", playbackBody("fifth", "native", "start", 0, 0)); w.Code != 409 {
		t.Fatal("stop bypassed cap", w.Code)
	}
	p := call("sentence", "start", 1, 0)
	p = call("sentence", "ended", 1, p.Active.Fence)
	if p.Cursor != 2 {
		t.Fatal(p)
	}
	p = call("gap-stop", "stop", 0, p.Revision)
	if p.Cursor != 1 || p.WholeStarts != 4 {
		t.Fatal(p)
	}
	p = call("first-again", "start", 1, 0)
	if p.Active.Step != 1 || p.Active.Offset != 0 {
		t.Fatal(p)
	}
	if w := f.call("POST", "/one/playback", playbackBody("stale", "native", "stop", 0, p.Revision-1)); w.Code != 409 {
		t.Fatal("stale stop accepted", w.Code)
	}
	if w := f.call("POST", "/one/playback", playbackBody("foreign", "other", "stop", 0, p.Revision)); w.Code != 409 {
		t.Fatal("foreign lease stopped", w.Code)
	}
}

// The caller retains its observed fence when the committed response is lost.
// Reopening the handler must recover only that admission's uninterrupted owner.
func TestDictationStopLostAcknowledgmentRecovery(t *testing.T) {
	for _, action := range []string{"start", "progress"} {
		t.Run(action, func(t *testing.T) {
			f := newPlaybackFixture(t)
			f.seed(t)
			p := playbackDecode(t, f.call("POST", "/one/playback", playbackBody("owned", "native", "start", 0, 0)))
			observed := 0
			if action == "progress" {
				observed = p.Revision
				p = playbackDecode(t, f.call("POST", "/one/playback", playbackBody("owned", "native", "progress", 0, p.Active.Fence)))
			}
			var err error
			f.h, err = newHandler(f.cfg)
			if err != nil {
				t.Fatal(err)
			}
			body := fmt.Sprintf(`{"id":"stop-lost","client":"native","action":"stop","step":0,"fence":%d,"admission":"owned"}`, observed)
			stopped := playbackDecode(t, f.call("POST", "/one/playback", body))
			if stopped.Active != nil || stopped.WholeStarts != 1 || stopped.FinalUsed != p.FinalUsed || stopped.Cursor != 1 || stopped.Listens[0].Done || !stopped.Listens[0].Stopped {
				t.Fatal(stopped)
			}
			retry := playbackDecode(t, f.call("POST", "/one/playback", body))
			if retry.Revision != stopped.Revision {
				t.Fatal("non-idempotent recovery")
			}
		})
	}
}

func TestDictationStopLostAcknowledgmentRejectsForeignLineage(t *testing.T) {
	for _, returnOwnership := range []bool{false, true} {
		t.Run(fmt.Sprint(returnOwnership), func(t *testing.T) {
			f := newPlaybackFixture(t)
			f.seed(t)
			p := playbackDecode(t, f.call("POST", "/one/playback", playbackBody("owned", "native", "start", 0, 0)))
			observed := p.Revision
			p = playbackDecode(t, f.call("POST", "/one/playback", playbackBody("owned", "native", "release", 0, p.Active.Fence)))
			p = playbackDecode(t, f.call("POST", "/one/playback", playbackBody("owned", "foreign", "resume", 0, p.Active.Fence)))
			p = playbackDecode(t, f.call("POST", "/one/playback", playbackBody("owned", "foreign", "release", 0, p.Active.Fence)))
			if returnOwnership {
				p = playbackDecode(t, f.call("POST", "/one/playback", playbackBody("owned", "native", "resume", 0, p.Active.Fence)))
			}
			body := fmt.Sprintf(`{"id":"stale","client":"native","action":"stop","step":0,"fence":%d,"admission":"owned"}`, observed)
			if w := f.call("POST", "/one/playback", body); w.Code != 409 {
				t.Fatal("adopted foreign lineage", w.Code)
			}
			f.cfg.dictationTransaction(f.owner, false, func(d *dictationData) error {
				if got := dictationFind(d, "one").Playback; got.Revision != p.Revision || got.Active.Offset != p.Active.Offset || got.Cursor != p.Cursor || got.WholeStarts != p.WholeStarts {
					t.Error("foreign ledger changed")
				}
				return nil
			})
		})
	}
}
