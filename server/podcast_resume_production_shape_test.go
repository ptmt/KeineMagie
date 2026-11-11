package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPodcastFailed2113Segments954TranslationsResumeAfterQuotaReset(t *testing.T) {
	root := t.TempDir()
	t.Setenv("PROVIDER_KEY_FILE", filepath.Join(root, "key"))
	_ = os.WriteFile(filepath.Join(root, "key"), []byte(strings.Repeat("k", 32)), 0600)
	t.Setenv("TRANSLATION_DAILY_ATTEMPTS", "100")
	calls := 0
	cfg := &serverConfig{authPath: filepath.Join(root, "auth.json"), historyPath: filepath.Join(root, "history.json"), httpClient: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		body := `{"models":[{"slug":"offered","display_name":"Synthetic","visibility":"list"}]}`
		if strings.HasSuffix(r.URL.Path, "responses") {
			calls++
			var request struct {
				Input []struct {
					Content string `json:"content"`
				} `json:"input"`
			}
			_ = json.NewDecoder(r.Body).Decode(&request)
			var input struct {
				Segments []podcastTranslationItem `json:"segments"`
			}
			_ = json.Unmarshal([]byte(request.Input[0].Content), &input)
			for _, item := range input.Segments {
				if item.ID < 954 {
					t.Fatalf("saved translation replayed: %d", item.ID)
				}
			}
			// Reconstruct request for the shared realistic Responses SSE fixture.
			raw, _ := json.Marshal(request)
			r.Body = io.NopCloser(strings.NewReader(string(raw)))
			body = podcastFixtureTranslationSSE(r)
		}
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(body))}, nil
	})}}
	if _, e := newHandler(cfg); e != nil {
		t.Fatal(e)
	}
	if e := cfg.provider.save("owner", providerCredential{AccessToken: "synthetic", Expires: time.Now().Add(time.Hour)}); e != nil {
		t.Fatal(e)
	}
	s, _ := openPodcastStore(filepath.Join(root, "podcasts", "jobs.json"))
	now := time.Now()
	_, _ = s.create("owner", "https://example.com/a.mp3", "de", now)
	j, _ := s.claim(now)
	for i := 0; i < 2113; i++ {
		segment := podcastSegment{Start: float64(i * 2), End: float64(i*2 + 1), Text: "word"}
		if i < 954 {
			segment.Translation = "saved translation"
		}
		j.Segments = append(j.Segments, segment)
	}
	j.State = "failed"
	j.Progress = 72
	j.Error = "personal batch translation failed or incomplete; saved progress retained"
	_ = s.update(j)
	quotaPath := filepath.Join(cfg.provider.dir, "quotas", sessionHash("owner")+".json")
	_ = os.MkdirAll(filepath.Dir(quotaPath), 0700)
	setQuota := func(day time.Time) {
		b, _ := json.Marshal(dailyTranslationQuota{Day: day.UTC().Format("2006-01-02"), Attempts: 100})
		if e := os.WriteFile(quotaPath, b, 0600); e != nil {
			t.Fatal(e)
		}
	}
	setQuota(now)
	if _, e := s.mutate("owner", j.ID, "retry", now); e != nil {
		t.Fatal(e)
	}
	j, _ = s.claim(now)
	p := &podcastService{cfg: cfg, store: s, fetchAudio: func(context.Context, string, string) error {
		t.Fatal("retained transcript caused ASR/refetch")
		return nil
	}}
	p.process(context.Background(), j)
	jobs, _ := s.list("owner")
	if jobs[0].State != "failed" || calls != 0 || jobs[0].Segments[953].Translation != "saved translation" {
		t.Fatal("quota rejection lost progress or sent inference")
	}
	// UTC date rollover makes yesterday's quota inapplicable, but never silently
	// retries a failed owner job. Only an explicit manual retry resumes it.
	setQuota(now.Add(-24 * time.Hour))
	unclaimed, e := s.claim(now)
	if e != nil || unclaimed.ID != "" {
		t.Fatal("quota rollover auto-retried terminal job")
	}
	if _, e = s.mutate("owner", j.ID, "retry", now); e != nil {
		t.Fatal(e)
	}
	j, _ = s.claim(now)
	p.process(context.Background(), j)
	jobs, _ = s.list("owner")
	if jobs[0].State != "completed" || len(jobs[0].Segments) != 2113 || calls != 19 {
		t.Fatalf("resume state=%s calls=%d", jobs[0].State, calls)
	}
	for i, segment := range jobs[0].Segments {
		if segment.Translation == "" || (i < 954 && segment.Translation != "saved translation") {
			t.Fatal("lost saved translation", i)
		}
	}
}
