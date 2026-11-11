package main

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPodcastFinalPartialCheckpointReplaysOnlyTail(t *testing.T) {
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	s.create("owner", "https://example.com/a.mp3", "de", time.Now())
	j, _ := s.claim(time.Now())
	calls := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		io.Copy(io.Discard, r.Body)
		calls++
		w.Header().Set("Content-Type", "application/x-ndjson")
		if calls == 1 {
			io.WriteString(w, "{\"type\":\"checkpoint\",\"chunk_index\":0,\"end_seconds\":600,\"segments\":[{\"start\":1,\"end\":2,\"text\":\"first\"}]}\n")
		} else if r.Header.Get("X-Resume-Offset") != "600" {
			t.Errorf("invalid final-tail offset %s", r.Header.Get("X-Resume-Offset"))
		}
		io.WriteString(w, "{\"type\":\"checkpoint\",\"chunk_index\":1,\"end_seconds\":660,\"segments\":[{\"start\":650,\"end\":652,\"text\":\"last\"}]}\n")
		if calls > 1 {
			io.WriteString(w, "{\"type\":\"complete\",\"duration_seconds\":660,\"language\":\"de\"}\n")
		}
	}))
	defer srv.Close()
	token := filepath.Join(t.TempDir(), "token")
	os.WriteFile(token, []byte(strings.Repeat("a", 64)), 0600)
	remote, _ := newPodcastRemote(srv.URL, token)
	p := &podcastService{store: s, fetchAudio: func(_ context.Context, _, path string) error { return os.WriteFile(path, []byte("fixture"), 0600) }}
	path, e := p.stageMedia(context.Background(), &j)
	if e != nil {
		t.Fatal(e)
	}
	if e = remote.transcribeResumable(context.Background(), path, &j, func() error { return s.update(j) }); e == nil {
		t.Fatal("accepted EOF before complete")
	}
	jobs, _ := s.list("owner")
	j = jobs[0]
	if j.Resume.End != 660 || j.Resume.Complete {
		t.Fatal("final checkpoint not retained")
	}
	if e = remote.transcribeResumable(context.Background(), path, &j, func() error { return s.update(j) }); e != nil {
		t.Fatal(e)
	}
	if len(j.Segments) != 2 || !j.Resume.Complete {
		t.Fatal("tail replay duplicated or lost segments")
	}
}

func TestPodcastMediaQuotaIgnoresSymbolicLinks(t *testing.T) {
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	s.create("owner", "https://example.com/a.mp3", "de", time.Now())
	j, _ := s.claim(time.Now())
	os.MkdirAll(s.mediaRoot(), 0700)
	// Even a retained-looking entry must not follow a filesystem link.
	other, _ := s.create("other", "https://example.com/b.mp3", "de", time.Now())
	outside := filepath.Join(t.TempDir(), "outside")
	os.WriteFile(outside, []byte("untouched"), 0600)
	os.Symlink(outside, s.mediaPath(other))
	p := &podcastService{store: s, fetchAudio: func(_ context.Context, _, path string) error { return os.WriteFile(path, []byte("fixture"), 0600) }}
	if _, e := p.stageMedia(context.Background(), &j); e != nil {
		t.Fatal(e)
	}
	b, _ := os.ReadFile(outside)
	if string(b) != "untouched" {
		t.Fatal("followed staging symlink")
	}
}

func TestPodcastStartupPreservesFailedJob(t *testing.T) {
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	s.create("owner", "https://example.com/a.mp3", "de", time.Now())
	j, _ := s.claim(time.Now())
	j.State = "failed"
	j.Error = "owner action required"
	s.update(j)
	before, _ := os.ReadFile(s.lock.path)
	if e := s.recoverInterrupted(time.Now()); e != nil {
		t.Fatal(e)
	}
	after, _ := os.ReadFile(s.lock.path)
	if string(before) != string(after) {
		t.Fatal("startup changed failed personal job")
	}
	next, _ := s.claim(time.Now())
	if next.ID != "" {
		t.Fatal("startup inferred for failed owner job")
	}
}
