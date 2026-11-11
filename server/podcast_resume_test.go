package main

import (
	"context"
	"path/filepath"
	"testing"
	"time"
)

func TestPodcastRestartImmediatelyRecoversWithoutAnotherAttempt(t *testing.T) {
	s, err := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	_, err = s.create("owner", "https://example.com/audio.mp3", "de", now)
	if err != nil {
		t.Fatal(err)
	}
	first, err := s.claim(now)
	if err != nil {
		t.Fatal(err)
	}
	// Called only after obtaining the exclusive cross-process worker flock.
	if err = s.recoverInterrupted(now); err != nil {
		t.Fatal(err)
	}
	next, err := s.claim(now)
	if err != nil {
		t.Fatal(err)
	}
	if next.ID != first.ID || next.Claim == first.Claim || next.Attempts != first.Attempts {
		t.Fatalf("restart did not resume same admission: first=%+v next=%+v", first, next)
	}
	if err = s.update(first); err == nil {
		t.Fatal("old process overwrote new claim")
	}
}

func TestPodcastProcessStopIsNotUserCancellation(t *testing.T) {
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	_, _ = s.create("owner", "https://example.com/audio.mp3", "de", time.Now())
	j, _ := s.claim(time.Now())
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	p := &podcastService{store: s, fetchAudio: func(ctx context.Context, _, _ string) error { return ctx.Err() }}
	p.process(ctx, j)
	jobs, _ := s.list("owner")
	if jobs[0].State != "queued" {
		t.Fatalf("shutdown became terminal %s", jobs[0].State)
	}
}
