package main

import (
	"encoding/json"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestEpisodeDeepLinkPublicShell(t *testing.T) {
	h := authHandler(t)
	for _, path := range []string{"/podcasts/episodes/the-nut-sisters-a1b2c3d4e5f6", "/podcasts/episodes/renamed-a1b2c3d4e5f6"} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != 200 || !strings.Contains(w.Body.String(), `src="/app.mjs"`) {
			t.Fatalf("deep shell %s: %d %s", path, w.Code, w.Body.String())
		}
		if strings.Contains(w.Body.String(), "a1b2c3d4e5f6") {
			t.Fatal("private metadata in shell")
		}
	}
	for _, path := range []string{"/podcasts/episodes/no-suffix", "/podcasts/episodes/title-A1B2C3D4E5F6", "/podcasts/episodes/title-a1b2c3d4e5f6/private"} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != 404 {
			t.Fatalf("invalid deep URL %s: %d", path, w.Code)
		}
	}
}

func TestEpisodePermalinkOwnerResolution(t *testing.T) {
	cfg := &serverConfig{authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json")}
	h, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	token, s, _ := cfg.auth.store.create("owner", time.Now())
	other, _, _ := cfg.auth.store.create("other", time.Now())
	store, _ := openPodcastStore(filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json"))
	job, e := store.create(s.UserID, "https://example.com/episode.mp3", "de", time.Now())
	if e != nil {
		t.Fatal(e)
	}
	// Hash the exact opaque ID; never truncate or normalize the supplied token.
	key := sessionHash(job.ID)[:12]
	path := "/v1/podcasts/episodes/renamed-" + key
	if w := authCall(h, "GET", path, "", ""); w.Code != 401 {
		t.Fatalf("guest %d", w.Code)
	}
	if w := authCall(h, "GET", path, "", other); w.Code != 404 {
		t.Fatalf("foreign owner %d", w.Code)
	}
	w := authCall(h, "GET", path, "", token)
	var got podcastJob
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &got) != nil || got.ID != job.ID {
		t.Fatalf("resolve %d %s", w.Code, w.Body.String())
	}
	if w.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("cacheable private job")
	}
	if w := authCall(h, "GET", "/v1/podcasts/"+job.ID, "", token); w.Code != 200 {
		t.Fatalf("legacy %d", w.Code)
	}
}

func TestEpisodePermalinkCollisionFailsClosed(t *testing.T) {
	jobs := []podcastJob{{ID: "same", Owner: "owner"}, {ID: "same", Owner: "owner"}}
	if _, e := resolvePodcastPermalink(jobs, sessionHash("same")[:12]); e == nil {
		t.Fatal("ambiguous suffix accepted")
	}
	if _, e := resolvePodcastPermalink(jobs, "ABCDEF123456"); e == nil {
		t.Fatal("normalized malformed suffix")
	}
}
