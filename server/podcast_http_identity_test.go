package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestPodcastHTTPExistingSecurityBoundaries(t *testing.T) {
	t.Setenv("PODCAST_WORKER_URL", "")
	cfg := &serverConfig{authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json")}
	if _, e := newHandler(cfg); e != nil {
		t.Fatal(e)
	}
	native, session, _ := cfg.auth.store.create("owner", time.Now())
	foreign, _, _ := cfg.auth.store.create("foreign", time.Now())
	browser, _ := cfg.auth.store.createBrowser(native, session.UserID, time.Now())
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	sub, e := s.saveSubscription(session.UserID, "", podcastDiscovery{URL: "https://example.com/feed", Episodes: []podcastEpisode{{ID: "one", URL: "https://example.com/a.mp3"}}}, time.Now())
	if e != nil {
		t.Fatal(e)
	}
	j, e := s.createEpisode(session.UserID, "", "de", sub.ID, "one", "", time.Now())
	if e != nil {
		t.Fatal(e)
	}
	p := &podcastService{cfg: cfg, store: s}
	body, _ := json.Marshal(map[string]string{"feed_id": sub.ID, "episode_id": "one", "source_language": "de"})
	for _, tc := range []struct {
		name, token, csrf, origin string
		cookie                    bool
		want                      int
	}{{name: "guest", want: 401}, {name: "foreign", token: foreign, want: 404}, {name: "browser missing csrf", cookie: true, origin: newBrowserAuth(cfg).origin, want: 403}, {name: "browser foreign origin", cookie: true, origin: "https://evil.example", csrf: browserCSRF(browser), want: 403}, {name: "browser accepted", cookie: true, origin: newBrowserAuth(cfg).origin, csrf: browserCSRF(browser), want: 202}} {
		t.Run(tc.name, func(t *testing.T) {
			r := httptest.NewRequest("POST", "/v1/podcasts", strings.NewReader(string(body)))
			if tc.token != "" {
				r.Header.Set("Authorization", "Bearer "+tc.token)
			}
			if tc.cookie {
				r.AddCookie(&http.Cookie{Name: browserCookie, Value: browser})
				r.Header.Set("Origin", tc.origin)
				r.Header.Set("X-CSRF-Token", tc.csrf)
			}
			w := httptest.NewRecorder()
			p.handle(w, r)
			if w.Code != tc.want {
				t.Fatalf("status=%d", w.Code)
			}
			if tc.want != 202 && strings.Contains(w.Body.String(), j.ID) {
				t.Fatal("foreign job disclosed")
			}
		})
	}
}

func TestPodcastHTTPConcurrentNewImport(t *testing.T) {
	t.Setenv("PODCAST_WORKER_URL", "")
	t.Setenv("PROVIDER_KEY_FILE", filepath.Join(t.TempDir(), "key"))
	if e := os.WriteFile(os.Getenv("PROVIDER_KEY_FILE"), []byte(strings.Repeat("k", 32)), 0600); e != nil {
		t.Fatal(e)
	}
	var worker, provider, source atomic.Int32
	cfg := &serverConfig{authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json"), httpClient: &http.Client{Transport: transportFunc(func(*http.Request) (*http.Response, error) {
		provider.Add(1)
		return nil, errors.New("provider must not be called")
	})}}
	if _, e := newHandler(cfg); e != nil {
		t.Fatal(e)
	}
	token, session, _ := cfg.auth.store.create("owner", time.Now())
	if e := cfg.provider.save(session.UserID, providerCredential{AccessToken: "synthetic", Expires: time.Now().Add(time.Hour)}); e != nil {
		t.Fatal(e)
	}
	path := filepath.Join(t.TempDir(), "jobs.json")
	s, _ := openPodcastStore(path)
	sub, e := s.saveSubscription(session.UserID, "", podcastDiscovery{URL: "https://example.com/feed", Episodes: []podcastEpisode{{ID: "one", URL: "https://example.com/audio.mp3"}}}, time.Now())
	if e != nil {
		t.Fatal(e)
	}
	f := podcastFixtureFetcher(t, func(w http.ResponseWriter, r *http.Request) { source.Add(1); http.Error(w, "unexpected", 503) })
	p := &podcastService{cfg: cfg, store: s, sourceFetcher: &f, remote: &podcastRemote{endpoint: "http://worker.invalid", http: &http.Client{Transport: transportFunc(func(*http.Request) (*http.Response, error) {
		worker.Add(1)
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(`{"version":1,"ready":true,"capacity":1}`))}, nil
	})}}}
	p.running.Store(true)
	srv := httptest.NewServer(http.HandlerFunc(p.handle))
	defer srv.Close()
	ids := make(chan string, 20)
	var wg sync.WaitGroup
	for n := 0; n < 20; n++ {
		wg.Add(1)
		go func(n int) {
			defer wg.Done()
			body := `{"url":"https://example.com/audio.mp3","source_language":"de"}`
			if n%2 == 0 {
				b, _ := json.Marshal(map[string]string{"feed_id": sub.ID, "episode_id": "one", "source_language": "de"})
				body = string(b)
			}
			req, _ := http.NewRequest("POST", srv.URL+"/v1/podcasts", strings.NewReader(body))
			req.Header.Set("Authorization", "Bearer "+token)
			resp, e := srv.Client().Do(req)
			if e != nil {
				t.Error(e)
				return
			}
			defer resp.Body.Close()
			var j podcastJob
			if e = json.NewDecoder(resp.Body).Decode(&j); e != nil || resp.StatusCode != 202 || j.ID == "" {
				t.Error("HTTP import failed", resp.StatusCode, e)
				return
			}
			ids <- j.ID
		}(n)
	}
	wg.Wait()
	close(ids)
	id := ""
	count := 0
	for got := range ids {
		count++
		if id != "" && got != id {
			t.Error("duplicate HTTP IDs")
		}
		id = got
	}
	if count != 20 {
		t.Errorf("responses=%d", count)
	}
	reopened, _ := openPodcastStore(path)
	again, e := reopened.create(session.UserID, "https://example.com/audio.mp3", "de", time.Now())
	if e != nil || again.ID != id {
		t.Fatal("identity changed across reopen", e)
	}
	d, e := reopened.read()
	if e != nil || len(d.Jobs) != 1 || d.Budgets[sessionHash(session.UserID)].Attempts != 1 {
		t.Fatal("duplicate reservations", e)
	}
	if worker.Load() != 1 || provider.Load() != 0 || source.Load() != 0 {
		t.Errorf("upstream calls worker=%d provider=%d source=%d", worker.Load(), provider.Load(), source.Load())
	}
}

func TestPodcastHTTPExistingBeforeReadiness(t *testing.T) {
	t.Setenv("PODCAST_WORKER_URL", "")
	var upstream atomic.Int32
	cfg := &serverConfig{authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json"), httpClient: &http.Client{Transport: transportFunc(func(*http.Request) (*http.Response, error) {
		upstream.Add(1)
		return &http.Response{StatusCode: 503, Body: io.NopCloser(strings.NewReader("")), Header: http.Header{}}, nil
	})}}
	if _, e := newHandler(cfg); e != nil {
		t.Fatal(e)
	}
	token, session, e := cfg.auth.store.create("owner", time.Now())
	if e != nil {
		t.Fatal(e)
	}
	path := filepath.Join(t.TempDir(), "jobs.json")
	store, e := openPodcastStore(path)
	if e != nil {
		t.Fatal(e)
	}
	sub, e := store.saveSubscription(session.UserID, "", podcastDiscovery{URL: "https://example.com/feed", Episodes: []podcastEpisode{{ID: "one", URL: "https://example.com/a.mp3"}}}, time.Now())
	if e != nil {
		t.Fatal(e)
	}
	job, e := store.createEpisode(session.UserID, "", "de", sub.ID, "one", "", time.Now())
	if e != nil {
		t.Fatal(e)
	}
	f := podcastFixtureFetcher(t, func(w http.ResponseWriter, r *http.Request) { upstream.Add(1); http.Error(w, "offline", 503) })
	for restart := 0; restart < 2; restart++ {
		reopened, e := openPodcastStore(path)
		if e != nil {
			t.Fatal(e)
		}
		p := &podcastService{cfg: cfg, store: reopened, sourceFetcher: &f, remote: &podcastRemote{endpoint: "http://worker.invalid", http: cfg.httpClient}}
		p.running.Store(true)
		server := httptest.NewServer(http.HandlerFunc(p.handle))
		var wg sync.WaitGroup
		for n := 0; n < 12; n++ {
			wg.Add(1)
			go func(n int) {
				defer wg.Done()
				body := `{"url":"https://example.com/a.mp3","source_language":"de"}`
				if n%2 == 0 {
					b, _ := json.Marshal(map[string]string{"feed_id": sub.ID, "episode_id": "one", "source_language": "de"})
					body = string(b)
				}
				req, _ := http.NewRequest("POST", server.URL+"/v1/podcasts", strings.NewReader(body))
				req.Header.Set("Authorization", "Bearer "+token)
				resp, e := server.Client().Do(req)
				if e != nil {
					t.Error(e)
					return
				}
				defer resp.Body.Close()
				var got podcastJob
				json.NewDecoder(resp.Body).Decode(&got)
				if resp.StatusCode != 202 || got.ID != job.ID {
					t.Errorf("existing HTTP status=%d same_id=%v", resp.StatusCode, got.ID == job.ID)
				}
			}(n)
		}
		wg.Wait()
		server.Close()
	}
	if upstream.Load() != 0 {
		t.Errorf("duplicate upstream calls=%d", upstream.Load())
	}
	d, e := store.read()
	if e != nil || len(d.Jobs) != 1 || d.Budgets[sessionHash(session.UserID)].Attempts != 1 {
		t.Fatal("duplicate changed persisted jobs/budget", e)
	}
}
