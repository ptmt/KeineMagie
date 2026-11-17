package main

import (
	"fmt"
	"testing"
	"time"
)

func TestDailyEntrySpringAndFallCalendarDayLengths(t *testing.T) {
	for _, tc := range []struct {
		name, start string
		hours       int
	}{{"spring", "2026-03-28T23:00:00Z", 23}, {"fall", "2026-10-24T22:00:00Z", 25}} {
		t.Run(tc.name, func(t *testing.T) {
			f := dailyFixture(t)
			start, e := time.Parse(time.RFC3339, tc.start)
			if e != nil {
				t.Fatal(e)
			}
			now := start
			f.cfg.auth.now = func() time.Time { return now }
			if e := f.cfg.auth.store.lock.locked(func() error {
				d, e := f.cfg.auth.store.read()
				if e != nil {
					return e
				}
				s := d.Sessions[sessionHash(f.token)]
				s.Expires = time.Date(2099, 1, 1, 0, 0, 0, 0, time.UTC)
				d.Sessions[sessionHash(f.token)] = s
				return f.cfg.auth.store.write(d)
			}); e != nil {
				t.Fatal(e)
			}
			for index, delta := range []time.Duration{0, time.Duration(tc.hours)*time.Hour - time.Second, time.Duration(tc.hours) * time.Hour} {
				now = start.Add(delta)
				if w := dailyCall(f, fmt.Sprintf("clock-%d", index), "Europe/Berlin"); w.Code != 200 {
					t.Fatal(w.Code, w.Body.String())
				}
				want := int32(1)
				if index == 2 {
					want = 2
				}
				if f.calls.Load() != want {
					t.Fatalf("local day duration %dh: calls=%d want=%d", tc.hours, f.calls.Load(), want)
				}
				if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error {
					for i := range d.Turns {
						d.Turns[i].Attempt = &coachAttempt{Outcome: "correct"}
					}
					return nil
				}); e != nil {
					t.Fatal(e)
				}
			}
		})
	}
}
