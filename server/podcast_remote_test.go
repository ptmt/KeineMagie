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

func TestPodcastRemoteRejectsUntrustedResponses(t *testing.T) {
	for _, body := range []string{
		`{"version":2,"segments":[{"start":0,"end":1,"text":"hi"}]}`,
		`{"version":1,"segments":[]}`,
		`{"version":1,"segments":[{"start":0,"end":10801,"text":"hi"}]}`,
		`{"version":1,"segments":[{"start":0,"end":2,"text":"hi"},{"start":1,"end":3,"text":"hi"}]}`,
		`{"version":1,"segments":[{"start":0,"end":1,"text":"` + strings.Repeat("x", 8001) + `"}]}`,
		strings.Repeat("x", (1<<20)+1),
	} {
		t.Run("invalid", func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte(body)) }))
			defer srv.Close()
			token := filepath.Join(t.TempDir(), "token")
			os.WriteFile(token, []byte(strings.Repeat("a", 64)), 0600)
			c, e := newPodcastRemote(srv.URL, token)
			if e != nil {
				t.Fatal(e)
			}
			audio := filepath.Join(t.TempDir(), "audio")
			os.WriteFile(audio, []byte("audio"), 0600)
			if _, e = c.transcribe(context.Background(), audio, "de"); e == nil {
				t.Fatal("accepted invalid response")
			}
		})
	}
}

func TestPodcastRemoteRealContainer(t *testing.T) {
	if os.Getenv("PODCAST_CONTAINER_TEST") != "1" {
		t.Skip("isolated container fixture only")
	}
	c, e := newPodcastRemote(os.Getenv("PODCAST_WORKER_URL"), os.Getenv("PODCAST_WORKER_TOKEN_FILE"))
	if e != nil {
		t.Fatal(e)
	}
	if e = c.ready(context.Background()); e != nil {
		t.Fatal(e)
	}
	t.Setenv("PROVIDER_KEY_FILE", filepath.Join(t.TempDir(), "key"))
	os.WriteFile(os.Getenv("PROVIDER_KEY_FILE"), []byte(strings.Repeat("k", 32)), 0600)
	cfg := &serverConfig{authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json"), httpClient: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		body := `{"models":[{"slug":"offered","display_name":"Synthetic","visibility":"list"}]}`
		if strings.HasSuffix(r.URL.Path, "responses") {
			body = podcastFixtureTranslationSSE(r)
		}
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(body))}, nil
	})}}
	// Do not configure the background handler runner: drive one durable claim in
	// this isolated test while retaining the real owner-provider path.
	endpoint := os.Getenv("PODCAST_WORKER_URL")
	t.Setenv("PODCAST_WORKER_URL", "")
	if _, e = newHandler(cfg); e != nil {
		t.Fatal(e)
	}
	t.Setenv("PODCAST_WORKER_URL", endpoint)
	if e = cfg.provider.save("owner", providerCredential{AccessToken: "synthetic-owner", Expires: time.Now().Add(time.Hour)}); e != nil {
		t.Fatal(e)
	}
	store, e := openPodcastStore(filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json"))
	if e != nil {
		t.Fatal(e)
	}
	p := &podcastService{cfg: cfg, store: store, remote: c, fetchAudio: func(ctx context.Context, url, path string) error {
		b, e := os.ReadFile("/fixture/speech.aiff")
		if e != nil {
			return e
		}
		return os.WriteFile(path, b, 0600)
	}}
	if _, e = store.create("owner", "https://example.com/speech.mp3", "de", time.Now()); e != nil {
		t.Fatal(e)
	}
	j, e := store.claim(time.Now())
	if e != nil {
		t.Fatal(e)
	}
	p.process(context.Background(), j)
	jobs, e := store.list("owner")
	if e != nil || len(jobs) != 1 || jobs[0].State != "completed" || len(jobs[0].Segments) == 0 || jobs[0].Segments[0].Translation == "" {
		t.Fatalf("pipeline %+v %v", jobs, e)
	}
	text := ""
	for _, s := range jobs[0].Segments {
		text += s.Text
	}
	if !strings.Contains(strings.ToLower(text), "deutsch") {
		t.Fatal("missing real speech")
	}
	t.Log("durable claim -> authenticated container recognition -> synthetic owner translation -> completed: PASS")
}

func TestPodcastRemoteConfiguredFailClosed(t *testing.T) {
	t.Setenv("PODCAST_WORKER_URL", "http://127.0.0.1:1")
	t.Setenv("PODCAST_WORKER_TOKEN_FILE", filepath.Join(t.TempDir(), "missing"))
	t.Setenv("PODCAST_LOCAL_WORKER", "1")
	t.Setenv("PODCAST_WHISPER_BIN", "/should-not-be-used")
	p, e := newPodcasts(&serverConfig{historyPath: filepath.Join(t.TempDir(), "history.json")})
	if e != nil {
		t.Fatal(e)
	}
	if p.ready() == nil || p.whisper != "" {
		t.Fatal("invalid remote configuration must never fall back to local executables")
	}
}

func TestPodcastRemoteProtocol(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer "+strings.Repeat("a", 64) {
			t.Error("missing dedicated auth")
		}
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/internal/podcast/ready" {
			w.Write([]byte(`{"version":1,"ready":true,"capacity":1}`))
			return
		}
		if r.Header.Get("X-Podcast-Language") != "de" || r.Header.Get("X-Podcast-Version") != "1" {
			t.Error("protocol headers")
		}
		w.Write([]byte(`{"version":1,"segments":[{"start":0,"end":1,"text":" Hallo ","translation":"untrusted"}]}`))
	}))
	defer server.Close()
	token := filepath.Join(t.TempDir(), "token")
	os.WriteFile(token, []byte(strings.Repeat("a", 64)), 0600)
	c, e := newPodcastRemote(server.URL, token)
	if e != nil {
		t.Fatal(e)
	}
	if e = c.ready(context.Background()); e != nil {
		t.Fatal(e)
	}
	audio := filepath.Join(t.TempDir(), "audio")
	os.WriteFile(audio, []byte("fixture"), 0600)
	segments, e := c.transcribe(context.Background(), audio, "de")
	if e != nil || len(segments) != 1 || segments[0].Text != "Hallo" || segments[0].Translation != "" {
		t.Fatalf("%+v %v", segments, e)
	}
}
