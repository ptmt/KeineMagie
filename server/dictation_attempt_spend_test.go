package main

import (
	"path/filepath"
	"testing"
)

func TestDictationReleasedAttemptIsNotUnsettledSpend(t *testing.T) {
	f := newPlaybackFixture(t)
	root := filepath.Join(filepath.Dir(f.cfg.historyPath), "dictations")
	ticket, err := dictationPrepareAttempt(root, f.owner, "asset/0")
	if err != nil {
		t.Fatal(err)
	}
	if err = dictationReleasePrepared(root, ticket); err != nil {
		t.Fatal(err)
	}
	got := f.cfg.dictationSpeechSpend(f.owner)
	if got.UnsettledReservations != 0 {
		t.Fatalf("proven never-sent release misleadingly pending: %+v", got)
	}
	if got.ReportedMicroUSD != nil {
		t.Fatal("release invented provider receipt")
	}
	if got.ReservedMicroUSD != dictationAttemptMicroUSD {
		t.Fatal("original reservation audit removed")
	}
}

func TestDictationAttemptedUsageStillHasUncertainLiability(t *testing.T) {
	f := newPlaybackFixture(t)
	root := filepath.Join(filepath.Dir(f.cfg.historyPath), "dictations")
	ticket, err := dictationPrepareAttempt(root, f.owner, "asset/0")
	if err != nil {
		t.Fatal(err)
	}
	c := dictationOpenAIConfig{chars: 1800, seconds: 10, dailyRequests: 2, dailyChars: 100, dailySeconds: 20}
	if err = dictationMarkAttempted(root, ticket, c, "Hallo.", f.owner, 0); err != nil {
		t.Fatal(err)
	}
	u := dictationSpeechUsage{InputTokens: 10, OutputTokens: 20}
	u.Input.TextTokens = 10
	u.Output.AudioTokens = 20
	if err = dictationRecordUsage(root, ticket, u); err != nil {
		t.Fatal(err)
	}
	got := f.cfg.dictationSpeechSpend(f.owner)
	if got.UnsettledReservations != 1 {
		t.Fatalf("partial usage hid unresolved liability: %+v", got)
	}
}
