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

func TestPodcastResumeRejectsInvalidCheckpoint(t *testing.T) {
	for _, body := range []string{
		`{"type":"checkpoint","chunk_index":1,"end_seconds":600,"segments":[]}`,
		`{"type":"checkpoint","chunk_index":0,"end_seconds":601,"segments":[]}`,
		`{"type":"checkpoint","chunk_index":0,"end_seconds":600,"segments":[{"start":599,"end":601,"text":"bad"}]}`,
		`{"type":"checkpoint","chunk_index":0,"end_seconds":600,"segments":[{"start":1,"end":4,"text":"a"},{"start":3,"end":5,"text":"b"}]}`,
		`{"type":"complete","duration_seconds":600,"language":"de"}`,
		`{"type":"error","code":"recognition_failed"}`,
	} {
		t.Run("invalid", func(t *testing.T) {
			s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
			_, _ = s.create("owner", "https://example.com/a.mp3", "de", time.Now())
			j, _ := s.claim(time.Now())
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				_, _ = io.Copy(io.Discard, r.Body)
				w.Header().Set("Content-Type", "application/x-ndjson")
				io.WriteString(w, body+"\n")
			}))
			defer srv.Close()
			token := filepath.Join(t.TempDir(), "token")
			_ = os.WriteFile(token, []byte(strings.Repeat("a", 64)), 0600)
			remote, _ := newPodcastRemote(srv.URL, token)
			p := &podcastService{store: s, fetchAudio: func(_ context.Context, _, path string) error { return os.WriteFile(path, []byte("bytes"), 0600) }}
			path, e := p.stageMedia(context.Background(), &j)
			if e != nil {
				t.Fatal(e)
			}
			if e = remote.transcribeResumable(context.Background(), path, &j, func() error { return s.update(j) }); e == nil {
				t.Fatal("accepted invalid checkpoint")
			}
			jobs, _ := s.list("owner")
			if jobs[0].Resume.End != 0 || len(jobs[0].Segments) != 0 {
				t.Fatal("invalid checkpoint persisted")
			}
		})
	}
}
