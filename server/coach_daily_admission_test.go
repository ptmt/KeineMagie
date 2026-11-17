package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestDailyEntrySharedQuotaExhaustionAndReadOnlyGET(t *testing.T) {
	t.Setenv("TRANSLATION_DAILY_ATTEMPTS", "1")
	f := dailyFixture(t)
	r := httptest.NewRequest("GET", "/v1/learning/coach", nil)
	r.Header.Set("Authorization", "Bearer "+f.token)
	w := httptest.NewRecorder()
	f.h.ServeHTTP(w, r)
	if w.Code != 200 || len(f.read(t).DailyClaims) != 0 || f.calls.Load() != 0 {
		t.Fatal("GET admitted daily inference")
	}
	if w := f.call(coachInput{Action: "practice", RequestID: "explicit", Locale: "en"}); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error { d.Turns[0].Attempt = &coachAttempt{Outcome: "correct"}; return nil }); e != nil {
		t.Fatal(e)
	}
	if w := dailyCall(f, "daily", "Europe/Berlin"); w.Code != http.StatusTooManyRequests {
		t.Fatal("daily bypassed existing personal quota", w.Code, w.Body.String())
	}
	if w := dailyCall(f, "reload", "Europe/Berlin"); w.Code != 200 || f.calls.Load() != 1 {
		t.Fatal("quota failure autoretried")
	}
	d := f.read(t)
	if len(d.Turns) != 2 || d.Turns[1].State != "failed" {
		t.Fatal("quota failure not recoverable")
	}
}

func TestDailyEntryStorageFailureAndCancelBeforeClaim(t *testing.T) {
	f := dailyFixture(t)
	if w := f.call(coachInput{Action: "cancel", TurnID: "first", RequestID: "cancel", Locale: "en"}); w.Code != 200 {
		t.Fatal(w.Code)
	}
	if w := dailyCall(f, "first", "Europe/Berlin"); w.Code != 200 || f.calls.Load() != 0 {
		t.Fatal("cancel did not fence daily admission")
	}
	path := f.cfg.coachStore(f.owner).lock.path
	if e := os.Remove(path); e != nil {
		t.Fatal(e)
	}
	if e := os.Mkdir(path, 0700); e != nil {
		t.Fatal(e)
	}
	if w := dailyCall(f, "storage", "Europe/Berlin"); w.Code != 503 || f.calls.Load() != 0 {
		t.Fatal("storage failure spent", w.Code)
	}
}

func TestDailyEntryOwnerScopeAndNoFallback(t *testing.T) {
	f := dailyFixture(t)
	if w := dailyCall(f, "owner-a", "Europe/Berlin"); w.Code != 200 {
		t.Fatal(w.Code)
	}
	otherToken, other, e := f.cfg.auth.store.create("other-owner", f.cfg.auth.now())
	if e != nil {
		t.Fatal(e)
	}
	f.token = otherToken
	f.owner = other.UserID
	if w := dailyCall(f, "owner-b", "Europe/Berlin"); w.Code != 503 {
		t.Fatal("owner borrowed provider", w.Code)
	}
	if f.calls.Load() != 1 {
		t.Fatal("paid/provider fallback invoked")
	}
	d := f.read(t)
	if len(d.DailyClaims) != 1 || len(d.Turns) != 1 || d.Turns[0].ID != "owner-b" {
		t.Fatal("cross-owner claim leak")
	}
}
