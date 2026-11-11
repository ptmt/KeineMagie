package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPodcastExpiredStageCannotMixNewMediaAndOldTranscript(t *testing.T) {
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	_, _ = s.create("owner", "https://example.com/a.mp3", "de", time.Now())
	j, _ := s.claim(time.Now())
	content := "first bytes"
	p := &podcastService{store: s, fetchAudio: func(_ context.Context, _, path string) error { return os.WriteFile(path, []byte(content), 0600) }}
	path, e := p.stageMedia(context.Background(), &j)
	if e != nil {
		t.Fatal(e)
	}
	j.Resume.End = 600
	j.Segments = []podcastSegment{{Start: 1, End: 2, Text: "old media"}}
	_ = s.update(j)
	_ = os.Remove(path)
	content = "changed bytes"
	if _, e = p.stageMedia(context.Background(), &j); e == nil {
		t.Fatal("mixed new bytes with old transcript")
	}
}

func TestPodcastMediaRetentionLimitsAndDelete(t *testing.T) {
	t.Setenv("PODCAST_MAX_BYTES", "16")
	t.Setenv("PODCAST_MEDIA_MAX_BYTES", "20")
	t.Setenv("PODCAST_RESUME_TTL_SECONDS", "60")
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	_, _ = s.create("owner", "https://example.com/a.mp3", "de", time.Now())
	j, _ := s.claim(time.Now())
	p := &podcastService{store: s, fetchAudio: func(_ context.Context, _, path string) error { return os.WriteFile(path, []byte("12345678"), 0600) }}
	path, e := p.stageMedia(context.Background(), &j)
	if e != nil {
		t.Fatal(e)
	}
	if _, e = s.mutate("owner", j.ID, "cancel", time.Now()); e != nil {
		t.Fatal(e)
	}
	if e = s.cleanupMedia(time.Now().Add(59 * time.Second)); e != nil {
		t.Fatal(e)
	}
	if _, e = os.Stat(path); e != nil {
		t.Fatal("canceled stage not retained", e)
	}
	_, _ = s.create("owner", "https://example.com/b.mp3", "de", time.Now())
	other, _ := s.claim(time.Now())
	if _, e = p.stageMedia(context.Background(), &other); e == nil || !strings.Contains(e.Error(), "cap") {
		t.Fatal("global cap ignored", e)
	}
	if e = s.cleanupMedia(time.Now().Add(61 * time.Second)); e != nil {
		t.Fatal(e)
	}
	if _, e = os.Stat(path); !errors.Is(e, os.ErrNotExist) {
		t.Fatal("expired stage retained")
	}
	otherPath, e := p.stageMedia(context.Background(), &other)
	if e != nil {
		t.Fatal(e)
	}
	_, _ = s.mutate("owner", other.ID, "cancel", time.Now())
	_, e = s.mutate("owner", other.ID, "delete", time.Now())
	if e != nil {
		t.Fatal(e)
	}
	if _, e = os.Stat(otherPath); !errors.Is(e, os.ErrNotExist) {
		t.Fatal("deleted stage retained")
	}
}
