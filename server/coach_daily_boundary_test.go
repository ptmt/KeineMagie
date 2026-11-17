package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestDailyEntryDispatchMidnightCannotSpendTwice(t *testing.T) {
	f := dailyFixture(t)
	if e := f.cfg.provider.save(f.owner, providerCredential{AccessToken: "synthetic", Expires: time.Date(2099, 1, 1, 0, 0, 0, 0, time.UTC)}); e != nil {
		t.Fatal(e)
	}
	var clock atomic.Int64
	clock.Store(time.Date(2026, 11, 17, 22, 59, 0, 0, time.UTC).Unix())
	f.cfg.auth.now = func() time.Time { return time.Unix(clock.Load(), 0) }
	started, release := make(chan struct{}), make(chan struct{})
	original := f.cfg.provider.client.Transport
	f.cfg.provider.client = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		if strings.Contains(r.URL.Path, "models") {
			select {
			case <-started:
			default:
				close(started)
				<-release
			}
		}
		return original.RoundTrip(r)
	})}
	f.reply = func(*http.Request) (string, error) { return "", context.DeadlineExceeded }
	done := make(chan *httptest.ResponseRecorder, 1)
	go func() { done <- dailyCall(f, "before-midnight", "Europe/Berlin") }()
	<-started
	clock.Add(120)
	close(release)
	if w := <-done; w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	if w := dailyCall(f, "after-midnight", "Europe/Berlin"); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	if f.calls.Load() != 1 {
		t.Fatal("two accepted requests on dispatch day", f.calls.Load())
	}
}

func TestDailyEntryLastAvailableSlot(t *testing.T) {
	for _, mode := range []string{"turns", "receipts"} {
		t.Run(mode, func(t *testing.T) {
			f := dailyFixture(t)
			if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error {
				if mode == "turns" {
					for i := 0; i < 249; i++ {
						d.Turns = append(d.Turns, coachTurn{ID: strings.Repeat("x", i+1), State: "failed"})
					}
				} else {
					for i := 0; i < 9999; i++ {
						d.Receipts = append(d.Receipts, coachReceipt{ID: strings.Repeat("x", i%128+1)})
					}
				}
				return nil
			}); e != nil {
				t.Fatal(e)
			}
			if w := dailyCall(f, "last-slot", "Europe/Berlin"); w.Code != 200 || f.calls.Load() != 1 {
				t.Fatal("reserved slot rejected", w.Code, w.Body.String(), f.calls.Load())
			}
		})
	}
}
