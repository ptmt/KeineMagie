package main

import (
	"context"
	"net"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPodcastFeedAPIWithoutWorkerAndBrowserCSRF(t *testing.T) {
	t.Setenv("PODCAST_LOCAL_WORKER", "")
	cfg := &serverConfig{authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json")}
	_, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	native, s, _ := cfg.auth.store.create("owner", time.Now())
	browser, _ := cfg.auth.store.createBrowser(native, s.UserID, time.Now())
	store, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	f := podcastFixtureFetcher(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/rss+xml")
		w.Write([]byte(`<rss><channel><item><guid>one</guid><enclosure url="/a.mp3" type="audio/mpeg"/></item></channel></rss>`))
	})
	p := podcastService{cfg: cfg, store: store, sourceFetcher: &f}
	call := func(method, path, token, csrf string, cookie bool) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, path, strings.NewReader(`{"url":"http://fixture.example/feed"}`))
		if cookie {
			r.AddCookie(&http.Cookie{Name: browserCookie, Value: browser})
			r.Header.Set("Origin", newBrowserAuth(cfg).origin)
			r.Header.Set("X-CSRF-Token", csrf)
		} else {
			r.Header.Set("Authorization", "Bearer "+token)
		}
		w := httptest.NewRecorder()
		p.handle(w, r)
		return w
	}
	if w := call("POST", "/v1/podcasts/subscriptions", native, "", false); w.Code != 200 {
		t.Fatalf("discovery disabled with worker %d %s", w.Code, w.Body.String())
	}
	if w := call("POST", "/v1/podcasts/discover", "", "", true); w.Code != 403 {
		t.Fatal("CSRF", w.Code)
	}
	if w := call("POST", "/v1/podcasts/discover", "", browserCSRF(browser), true); w.Code != 200 {
		t.Fatal("browser", w.Code, w.Body.String())
	}
	if w := call("GET", "/v1/podcasts/subscriptions", "", "", false); w.Code != 401 {
		t.Fatal("auth", w.Code)
	}
	subs, err := store.subscriptions(s.UserID)
	if err != nil || len(subs) != 1 {
		t.Fatal("subscription fixture missing")
	}
	if w := call("GET", "/v1/podcasts/subscriptions/"+subs[0].ID+"/artwork", "", "", false); w.Code != 401 {
		t.Fatal("artwork guest auth", w.Code)
	}
	foreign, _, _ := cfg.auth.store.create("other", time.Now())
	if w := call("GET", "/v1/podcasts/subscriptions/"+subs[0].ID+"/artwork", foreign, "", false); w.Code != 404 {
		t.Fatal("artwork foreign owner", w.Code)
	}
	if w := call("GET", "/v1/podcasts/subscriptions/"+subs[0].ID+"/artwork", native, "", false); w.Code != 404 {
		t.Fatal("artwork missing fallback", w.Code)
	}
	jobs, _ := store.list(s.UserID)
	if len(jobs) != 0 {
		t.Fatal("AI work during discovery")
	}
}
func TestPodcastHTMLPolicyAndCancellation(t *testing.T) {
	for _, markup := range []string{`<audio src="http://127.0.0.1/a.mp3">`, `<script>const audio='https://public.example/a.mp3';</script>`, `<meta property="og:audio" content="https://example.com/a?secret=1">`} {
		f := podcastFixtureFetcher(t, func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "text/html")
			w.Write([]byte(markup))
		})
		if e := f.fetch(context.Background(), "http://fixture.example/page", filepath.Join(t.TempDir(), "audio")); e == nil {
			t.Fatal("accepted nonextractable page", markup)
		}
	}
	f := podcastFixtureFetcher(t, func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, "http://127.0.0.1/a.mp3", 302) })
	if e := f.fetch(context.Background(), "http://fixture.example/page", filepath.Join(t.TempDir(), "audio")); e == nil {
		t.Fatal("private redirect accepted")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, e := f.discover(ctx, "http://fixture.example/feed"); e == nil {
		t.Fatal("canceled fetch succeeded")
	}
	// The injected dial hook must not bypass DNS rejection, including mixed answers.
	f.lookup = func(context.Context, string) ([]net.IPAddr, error) {
		return []net.IPAddr{{IP: net.ParseIP("93.184.216.34")}, {IP: net.ParseIP("127.0.0.1")}}, nil
	}
	f.dial = func(context.Context, string, string) (net.Conn, error) {
		t.Fatal("dial after rejected DNS")
		return nil, nil
	}
	if _, e := f.discover(context.Background(), "http://fixture.example/feed"); e == nil {
		t.Fatal("mixed DNS accepted")
	}
}
