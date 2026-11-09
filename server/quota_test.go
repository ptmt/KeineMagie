package main

import (
	"testing"
	"time"
)

func TestTranslationDailyQuotaDurableAndSingleFlight(t *testing.T) {
	p := &providerService{dir: t.TempDir()}
	t.Setenv("TRANSLATION_DAILY_ATTEMPTS", "2")
	now := time.Now()
	release, e := p.beginTranslation("alice", now)
	if e != nil {
		t.Fatal(e)
	}
	if _, e = p.beginTranslation("alice", now); e == nil {
		t.Fatal("second active translation accepted")
	}
	release()
	release, e = p.beginTranslation("alice", now)
	if e != nil {
		t.Fatal(e)
	}
	release()
	p = &providerService{dir: p.dir}
	if _, e = p.beginTranslation("alice", now); e == nil {
		t.Fatal("daily limit lost across service restart")
	}
	release, e = p.beginTranslation("bob", now)
	if e != nil {
		t.Fatal("cross-user quota")
	}
	release()
	release, e = p.beginTranslation("alice", now.Add(24*time.Hour))
	if e != nil {
		t.Fatal("day reset")
	}
	release()
	t.Setenv("TRANSLATION_DAILY_ATTEMPTS", "invalid")
	if _, e = p.beginTranslation("bob", now); e == nil {
		t.Fatal("invalid quota did not fail closed")
	}
}
