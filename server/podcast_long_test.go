package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Synthetic batch provider replies preserve request IDs; no inference is claimed.
func podcastFixtureTranslationSSE(r *http.Request) string {
	var request struct {
		Input []struct {
			Content string `json:"content"`
		} `json:"input"`
	}
	if json.NewDecoder(r.Body).Decode(&request) != nil || len(request.Input) != 1 {
		return ""
	}
	var input struct {
		Segments []podcastTranslationItem `json:"segments"`
	}
	if json.Unmarshal([]byte(request.Input[0].Content), &input) != nil {
		return ""
	}
	for i := range input.Segments {
		input.Segments[i].Text = "Синтетический тест перевода."
	}
	b, _ := json.Marshal(map[string]any{"segments": input.Segments})
	return accountTranslationSSE(string(b), true, "response.completed")
}

func TestPodcastOrphanWorkspacesAreReclaimed(t *testing.T) {
	root := t.TempDir()
	abandoned := filepath.Join(root, "audio-abandoned")
	if err := os.Mkdir(abandoned, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(abandoned, "source.audio"), []byte("crashed upload"), 0600); err != nil {
		t.Fatal(err)
	}
	keep := filepath.Join(root, "jobs.json")
	if err := os.WriteFile(keep, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := cleanupPodcastWorkspaces(root); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(abandoned); !os.IsNotExist(err) {
		t.Fatal("orphan retained", err)
	}
	if _, err := os.Stat(keep); err != nil {
		t.Fatal("store removed", err)
	}
}

func TestPodcastStreamingDownloadBeyondOldLimit(t *testing.T) {
	u, _ := url.Parse("https://example.com/long.mp3")
	length := int64(41 << 20)
	client := &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 200, ContentLength: length, Header: http.Header{"Content-Type": []string{"audio/mpeg"}}, Body: io.NopCloser(io.LimitReader(podcastRepeatedByteReader{}, length))}, nil
	})}
	path := filepath.Join(t.TempDir(), "source.audio")
	if err := podcastFetchHTTP(context.Background(), u, path, client); err != nil {
		t.Fatal(err)
	}
	st, err := os.Stat(path)
	if err != nil || st.Size() != length {
		t.Fatalf("streamed size %v %v", st, err)
	}
	t.Setenv("PODCAST_MAX_BYTES", "1024")
	if err = podcastFetchHTTP(context.Background(), u, filepath.Join(t.TempDir(), "too-large"), client); err == nil {
		t.Fatal("configured upload cap ignored")
	}
}

type podcastRepeatedByteReader struct{}

func (podcastRepeatedByteReader) Read(b []byte) (int, error) {
	for i := range b {
		b[i] = 'x'
	}
	return len(b), nil
}

func TestPodcastBatchQuotaAdmissionIsAtomic(t *testing.T) {
	p := &providerService{dir: t.TempDir()}
	t.Setenv("TRANSLATION_DAILY_ATTEMPTS", "3")
	now := time.Now()
	if _, _, err := p.reserveTranslationPlan("owner", now, 4); err == nil {
		t.Fatal("oversized plan admitted")
	}
	consume, release, err := p.reserveTranslationPlan("owner", now, 2)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = p.beginTranslation("owner", now); err == nil {
		t.Fatal("reservation lost exclusivity")
	}
	if err = consume(now); err != nil {
		t.Fatal(err)
	}
	release() // Cancellation releases the one unsent attempt, no refund write.
	p = &providerService{dir: p.dir}
	consume, release, err = p.reserveTranslationPlan("owner", now, 2)
	if err != nil {
		t.Fatal("unsent attempt was charged across restart", err)
	}
	if err = consume(now); err != nil {
		t.Fatal(err)
	}
	if err = consume(now); err != nil {
		t.Fatal(err)
	}
	release()
	if _, err = p.beginTranslation("owner", now); err == nil {
		t.Fatal("actual attempts not charged")
	}
}

func TestPodcastStoreBoundedRead(t *testing.T) {
	path := filepath.Join(t.TempDir(), "jobs.json")
	f, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	if err = f.Truncate(podcastStoreMaxBytes + 1); err != nil {
		t.Fatal(err)
	}
	f.Close()
	if _, err = openPodcastStore(path); err == nil || !strings.Contains(err.Error(), "limit") {
		t.Fatal("oversized store not rejected before decoding", err)
	}
}

func TestPodcastLongPipelineResumesWithoutRecognition(t *testing.T) {
	t.Setenv("PROVIDER_KEY_FILE", filepath.Join(t.TempDir(), "key"))
	if err := os.WriteFile(os.Getenv("PROVIDER_KEY_FILE"), []byte(strings.Repeat("k", 32)), 0600); err != nil {
		t.Fatal(err)
	}
	calls := 0
	failSecond := true
	cfg := &serverConfig{authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json"), httpClient: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		body := `{"models":[{"slug":"offered","display_name":"Synthetic","visibility":"list"}]}`
		if strings.HasSuffix(r.URL.Path, "responses") {
			calls++
			var req struct {
				Input []struct {
					Content string `json:"content"`
				} `json:"input"`
			}
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatal(err)
			}
			var input struct {
				Segments []podcastTranslationItem `json:"segments"`
			}
			if err := json.Unmarshal([]byte(req.Input[0].Content), &input); err != nil {
				t.Fatal(err)
			}
			out := make([]podcastTranslationItem, len(input.Segments))
			for i, item := range input.Segments {
				out[i] = podcastTranslationItem{ID: item.ID, Text: "Перевод " + item.Text}
			}
			terminal := "response.completed"
			if calls == 2 && failSecond {
				terminal = "response.incomplete"
			}
			output, _ := json.Marshal(map[string]any{"segments": out})
			body = accountTranslationSSE(string(output), false, terminal)
		}
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(body))}, nil
	})}}
	if _, err := newHandler(cfg); err != nil {
		t.Fatal(err)
	}
	if err := cfg.provider.save("owner", providerCredential{AccessToken: "synthetic", Expires: time.Now().Add(time.Hour)}); err != nil {
		t.Fatal(err)
	}
	store, err := openPodcastStore(filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json"))
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	_, err = store.create("owner", "https://example.com/long.mp3", "de", now)
	if err != nil {
		t.Fatal(err)
	}
	job, err := store.claim(now)
	if err != nil {
		t.Fatal(err)
	}
	job.State = "translating"
	for i := 0; i < 180; i++ {
		job.Segments = append(job.Segments, podcastSegment{Start: float64(i * 60), End: float64(i*60 + 59), Text: strings.Repeat("Hallo ", 10)})
	}
	if err = store.update(job); err != nil {
		t.Fatal(err)
	}
	p := &podcastService{cfg: cfg, store: store, fetchAudio: func(context.Context, string, string) error { t.Fatal("checkpoint caused refetch"); return nil }}
	p.process(context.Background(), job)
	jobs, err := store.list("owner")
	if err != nil || jobs[0].State != "failed" || jobs[0].Segments[0].Translation == "" || jobs[0].Segments[50].Translation != "" {
		t.Fatalf("checkpoint failure: %+v %v", jobs, err)
	}
	quotaPath := filepath.Join(cfg.provider.dir, "quotas", sessionHash("owner")+".json")
	quotaBytes, err := os.ReadFile(quotaPath)
	if err != nil {
		t.Fatal(err)
	}
	var quota dailyTranslationQuota
	if err = json.Unmarshal(quotaBytes, &quota); err != nil {
		t.Fatal(err)
	}
	if quota.Attempts != 2 {
		t.Fatalf("unsent batches charged: got %d attempts, want 2", quota.Attempts)
	}
	if _, err = store.mutate("owner", job.ID, "retry", now); err != nil {
		t.Fatal(err)
	}
	job, err = store.claim(now)
	if err != nil {
		t.Fatal(err)
	}
	before := calls
	failSecond = false
	p.process(context.Background(), job)
	jobs, err = store.list("owner")
	if err != nil || jobs[0].State != "completed" || jobs[0].Progress != 100 || calls-before != 3 {
		t.Fatalf("resumed pipeline: state=%s calls=%d err=%v", jobs[0].State, calls-before, err)
	}
	for i, s := range jobs[0].Segments {
		if s.Translation == "" || s.Start != float64(i*60) || s.End != float64(i*60+59) {
			t.Fatal("lost text/timestamps", i)
		}
	}
}

func TestPodcastLongRemoteAndLimits(t *testing.T) {
	token := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(token, []byte(strings.Repeat("a", 64)), 0600); err != nil {
		t.Fatal(err)
	}
	audio := filepath.Join(t.TempDir(), "audio")
	if err := os.WriteFile(audio, []byte("offline wire fixture, not audio inference"), 0600); err != nil {
		t.Fatal(err)
	}
	segments := make([]podcastSegment, 180)
	for i := range segments {
		segments[i] = podcastSegment{Start: float64(i * 60), End: float64(i*60 + 59), Text: strings.Repeat("Hallo ", 20)}
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{"version": 1, "segments": segments})
	}))
	defer srv.Close()
	remote, err := newPodcastRemote(srv.URL, token)
	if err != nil {
		t.Fatal(err)
	}
	got, err := remote.transcribe(context.Background(), audio, "de")
	if err != nil || len(got) != 180 || got[179].End != 10799 {
		t.Fatalf("three hour timestamped response: %d %v", len(got), err)
	}
	t.Setenv("PODCAST_MAX_DURATION_SECONDS", "600")
	if _, err = remote.transcribe(context.Background(), audio, "de"); err == nil {
		t.Fatal("configured duration ignored")
	}
	t.Setenv("PODCAST_MAX_BYTES", "invalid")
	if _, err = remote.transcribe(context.Background(), audio, "de"); err == nil {
		t.Fatal("invalid configuration did not fail closed")
	}
}

func TestPodcastRetryPreservesTranslationCheckpoint(t *testing.T) {
	store, err := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	j, err := store.create("owner", "https://example.com/episode.mp3", "de", now)
	if err != nil {
		t.Fatal(err)
	}
	j, err = store.claim(now)
	if err != nil {
		t.Fatal(err)
	}
	j.Segments = []podcastSegment{{Start: 600, End: 610, Text: "Hallo", Translation: "Привет"}, {Start: 610, End: 620, Text: "Welt"}}
	j.State = "failed"
	if err = store.update(j); err != nil {
		t.Fatal(err)
	}
	if _, err = store.mutate("owner", j.ID, "retry", now); err != nil {
		t.Fatal(err)
	}
	resumed, err := store.claim(now)
	if err != nil || len(resumed.Segments) != 2 || resumed.Segments[0].Translation != "Привет" || resumed.State != "translating" {
		t.Fatalf("checkpoint lost: %+v %v", resumed, err)
	}
}
