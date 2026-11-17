package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDailyEntryResumesFailedAssessment(t *testing.T) {
	f := newAssessmentFixture(t)
	if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error {
		d.Turns[0].Attempt = &coachAttempt{ID: "saved-answer", Answer: "auf", AssessmentState: "failed"}
		return nil
	}); e != nil {
		t.Fatal(e)
	}
	if w := dailyCall(f, "resume", "Europe/Berlin"); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	d := f.read(t)
	if len(d.Turns) != 1 || f.calls.Load() != 0 || d.Turns[0].Attempt.Answer != "auf" {
		t.Fatal("unfinished answer was replaced", len(d.Turns), f.calls.Load())
	}
}

func TestDailyEntryCatalogCancellationAndQuota(t *testing.T) {
	for _, mode := range []string{"catalog-cancel", "response-cancel", "quota", "revocation"} {
		t.Run(mode, func(t *testing.T) {
			f := dailyFixture(t)
			started, release := make(chan struct{}), make(chan struct{})
			original := f.cfg.provider.client.Transport
			f.cfg.provider.client = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
				catalog := strings.Contains(r.URL.Path, "models")
				if catalog == (mode == "catalog-cancel") {
					close(started)
					<-release
				}
				return original.RoundTrip(r)
			})}
			done := make(chan *httptest.ResponseRecorder, 1)
			go func() { done <- dailyCall(f, "first", "Europe/Berlin") }()
			<-started
			if mode == "catalog-cancel" || mode == "response-cancel" {
				if w := f.call(coachInput{Action: "cancel", TurnID: "first", RequestID: "cancel", Locale: "en"}); w.Code != 200 {
					t.Fatal(w.Code)
				}
			}
			if mode == "revocation" {
				if e := f.cfg.auth.store.lock.locked(func() error {
					d, e := f.cfg.auth.store.read()
					if e != nil {
						return e
					}
					delete(d.Sessions, sessionHash(f.token))
					return f.cfg.auth.store.write(d)
				}); e != nil {
					t.Fatal(e)
				}
			}
			if mode != "revocation" {
				if w := dailyCall(f, "second-device", "Europe/Berlin"); w.Code != 200 {
					t.Fatal(w.Code)
				}
			}
			close(release)
			w := <-done
			d := f.read(t)
			if mode == "catalog-cancel" {
				if f.calls.Load() != 0 || d.Turns[0].State != "canceled" {
					t.Fatal("preflight cancel failed", f.calls.Load(), d.Turns[0])
				}
				return
			}
			if f.calls.Load() != 1 {
				t.Fatal("duplicate accepted request", f.calls.Load())
			}
			if mode == "revocation" {
				if w.Code != 401 || d.Turns[0].Result != nil {
					t.Fatal("revoked result committed", w.Code)
				}
			}
			if mode == "response-cancel" && d.Turns[0].State != "canceled" {
				t.Fatal("late result resurrected")
			}
			b, e := os.ReadFile(filepath.Join(f.cfg.provider.dir, "quotas", sessionHash(f.owner)+".json"))
			if e != nil {
				t.Fatal(e)
			}
			var q dailyTranslationQuota
			if e = json.Unmarshal(b, &q); e != nil || q.Attempts != 1 {
				t.Fatal("quota not shared", string(b), e)
			}
		})
	}
}

func TestDailyEntryCatalogFailureClaimAndInvalidZone(t *testing.T) {
	f := dailyFixture(t)
	if w := dailyCall(f, "bad", "Not/A_Zone"); w.Code != 400 {
		t.Fatal(w.Code)
	}
	if len(f.read(t).Receipts) != 0 {
		t.Fatal("invalid zone claimed")
	}
	f.cfg.provider.client = &http.Client{Transport: transportFunc(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 503, Header: http.Header{}, Body: io.NopCloser(strings.NewReader("unavailable"))}, nil
	})}
	if w := dailyCall(f, "first", "Europe/Berlin"); w.Code != 503 {
		t.Fatal(w.Code)
	}
	d := f.read(t)
	if len(d.Turns) != 1 || d.Turns[0].State != "failed" {
		t.Fatal("preflight failure not durable")
	}
	if w := dailyCall(f, "relaunch", "Europe/Berlin"); w.Code != 200 || f.calls.Load() != 0 {
		t.Fatal("preflight automatically retried")
	}
	if w := f.call(coachInput{Action: "entry", TimeZone: "Europe/Berlin", OwnerID: "foreign", RequestID: "wrong-owner", Locale: "en"}); w.Code != 409 {
		t.Fatal("owner check", w.Code)
	}
}
