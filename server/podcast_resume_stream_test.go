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

func TestPodcastNDJSONPersistsBeforeDisconnectAndResumes(t *testing.T) {
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	_, _ = s.create("owner", "https://example.com/audio.mp3", "de", time.Now())
	j, _ := s.claim(time.Now())
	calls := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.Copy(io.Discard, r.Body)
		calls++
		w.Header().Set("Content-Type", "application/x-ndjson")
		if r.Header.Get("Accept") != "application/x-ndjson" || r.Header.Get("X-Media-SHA256") == "" || r.Header.Get("X-Podcast-Job-ID") != j.ID {
			t.Error("missing stable identity")
		}
		if calls == 1 {
			io.WriteString(w, "{\"type\":\"checkpoint\",\"chunk_index\":0,\"end_seconds\":600,\"segments\":[{\"start\":1,\"end\":2,\"text\":\"first\"}]}\n")
			return
		}
		if r.Header.Get("X-Resume-Offset") != "600" {
			t.Errorf("resume header %s", r.Header.Get("X-Resume-Offset"))
		}
		io.WriteString(w, "{\"type\":\"checkpoint\",\"chunk_index\":1,\"end_seconds\":660,\"segments\":[{\"start\":650,\"end\":652,\"text\":\"last marker\"}]}\n{\"type\":\"complete\",\"duration_seconds\":660,\"language\":\"de\"}\n")
	}))
	defer srv.Close()
	token := filepath.Join(t.TempDir(), "token")
	_ = os.WriteFile(token, []byte(strings.Repeat("a", 64)), 0600)
	remote, _ := newPodcastRemote(srv.URL, token)
	p := &podcastService{store: s, remote: remote, fetchAudio: func(_ context.Context, _, path string) error {
		return os.WriteFile(path, []byte("synthetic media"), 0600)
	}}
	path, e := p.stageMedia(context.Background(), &j)
	if e != nil {
		t.Fatal(e)
	}
	if e = remote.transcribeResumable(context.Background(), path, &j, func() error { return s.update(j) }); e == nil {
		t.Fatal("accepted missing complete")
	}
	reopened, _ := openPodcastStore(s.lock.path)
	jobs, _ := reopened.list("owner")
	j = jobs[0]
	if j.Resume.End != 600 || len(j.Segments) != 1 || j.Resume.Complete {
		t.Fatalf("lost chunk %+v", j)
	}
	if e = remote.transcribeResumable(context.Background(), path, &j, func() error { return reopened.update(j) }); e != nil {
		t.Fatal(e)
	}
	if len(j.Segments) != 2 || j.Segments[1].Text != "last marker" || !j.Resume.Complete {
		t.Fatal("lost final chunk")
	}
}
