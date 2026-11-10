package main

import (
	"context"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPodcastURLPolicy(t *testing.T) {
	for _, raw := range []string{"file:///etc/passwd", "http://127.0.0.1/a.mp3", "https://user:secret@example.com/a.mp3", "https://example.com:8443/a.mp3", "https://[::1]/a.mp3", "https://example.com/a.mp3#secret", "https://example.com/a.mp3?token=secret"} {
		if _, err := podcastURL(raw); err == nil {
			t.Errorf("accepted %s", raw)
		}
	}
	if _, err := podcastURL("https://example.com/episode.mp3"); err != nil {
		t.Fatal(err)
	}
	for _, ip := range []string{"127.0.0.1", "10.0.0.1", "169.254.169.254", "::1", "fc00::1", "100.64.0.1", "192.0.0.1", "::ffff:127.0.0.1", "64:ff9b::a00:1"} {
		if podcastPublicIP(net.ParseIP(ip)) {
			t.Errorf("public %s", ip)
		}
	}
}
func TestPodcastDurableOwnershipRecovery(t *testing.T) {
	path := filepath.Join(t.TempDir(), "jobs.json")
	s, err := openPodcastStore(path)
	if err != nil {
		t.Fatal(err)
	}
	job, err := s.create("owner", "https://example.com/episode.mp3", "de", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if jobs, _ := s.list("other"); len(jobs) != 0 {
		t.Fatal("cross-owner leak")
	}
	claimed, err := s.claim(time.Now())
	if err != nil || claimed.ID != job.ID || claimed.State != "fetching" {
		t.Fatalf("claim: %+v %v", claimed, err)
	}
	s2, err := openPodcastStore(path)
	if err != nil {
		t.Fatal(err)
	}
	recovered, err := s2.claim(time.Now().Add(46 * time.Minute))
	if err != nil || recovered.ID != job.ID || recovered.Attempts != 2 {
		t.Fatalf("recovery: %+v %v", recovered, err)
	}
	if _, err = s2.mutate("other", job.ID, "retry", time.Now()); err == nil {
		t.Fatal("cross-owner retry")
	}
}
func TestPodcastAuthenticatedIsolationAndDisabledWorker(t *testing.T) {
	t.Setenv("PODCAST_LOCAL_WORKER", "")
	cfg := &serverConfig{authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json")}
	h, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	owner, s, _ := cfg.auth.store.create("owner", time.Now())
	other, _, _ := cfg.auth.store.create("other", time.Now())
	store, _ := openPodcastStore(filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json"))
	job, e := store.create(s.UserID, "https://example.com/episode.mp3", "de", time.Now())
	if e != nil {
		t.Fatal(e)
	}
	if w := authCall(h, "GET", "/v1/podcasts", "", ""); w.Code != 401 {
		t.Fatalf("unauth %d", w.Code)
	}
	if w := authCall(h, "GET", "/v1/podcasts/"+job.ID, "", other); w.Code != 404 {
		t.Fatalf("cross-owner %d", w.Code)
	}
	if w := authCall(h, "GET", "/v1/podcasts", "", owner); w.Code != 200 || !strings.Contains(w.Body.String(), job.ID) || !strings.Contains(w.Body.String(), `"worker_available":false`) {
		t.Fatalf("list %d %s", w.Code, w.Body.String())
	}
	if w := authCall(h, "POST", "/v1/podcasts", `{"url":"https://example.com/episode.mp3","source_language":"de"}`, owner); w.Code != 503 {
		t.Fatalf("disabled worker %d", w.Code)
	}
}
func TestPodcastCancelFencesStaleClaim(t *testing.T) {
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	j, _ := s.create("owner", "https://example.com/episode.mp3", "de", time.Now())
	claim, _ := s.claim(time.Now())
	if _, e := s.mutate("owner", j.ID, "cancel", time.Now()); e != nil {
		t.Fatal(e)
	}
	claim.State = "completed"
	if e := s.update(claim); e == nil {
		t.Fatal("stale worker completed canceled job")
	}
	jobs, _ := s.list("owner")
	if jobs[0].State != "canceled" {
		t.Fatal(jobs[0].State)
	}
}
func TestPodcastTranslationUsesOnlyOwnerProvider(t *testing.T) {
	t.Setenv("PROVIDER_KEY_FILE", filepath.Join(t.TempDir(), "key"))
	os.WriteFile(os.Getenv("PROVIDER_KEY_FILE"), []byte(strings.Repeat("k", 32)), 0600)
	calls := 0
	cfg := &serverConfig{authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json"), httpClient: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		calls++
		if r.Header.Get("Authorization") != "Bearer personal-owner" {
			t.Error("wrong account")
		}
		body := `{"models":[{"slug":"offered","display_name":"Offered","visibility":"list"}]}`
		if strings.HasSuffix(r.URL.Path, "responses") {
			body = accountTranslationSSE(`{"text":"Добрый день."}`, true, "response.completed")
		}
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(body))}, nil
	})}}
	_, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	cfg.provider.save("owner", providerCredential{AccessToken: "personal-owner", Expires: time.Now().Add(time.Hour)})
	p := &podcastService{cfg: cfg}
	got, e := p.translateSegment(context.Background(), "owner", translationInput{Text: "Guten Tag.", SourceLanguage: "de", TargetLanguage: "ru"})
	if e != nil || got != "Добрый день." {
		t.Fatalf("%q %v", got, e)
	}
	prior := calls
	if _, e = p.translateSegment(context.Background(), "other", translationInput{Text: "Guten Tag."}); e == nil || calls != prior {
		t.Fatal("unconnected owner used provider")
	}
}

// Optional integration gate uses installed tools and real speech, never a canned transcript.
func TestPodcastRealLocalWhisper(t *testing.T) {
	if os.Getenv("PODCAST_REAL_TEST") != "1" {
		t.Skip("set PODCAST_REAL_TEST=1 on configured Mac")
	}
	dir := t.TempDir()
	audio := filepath.Join(dir, "fixture.aiff")
	if out, e := exec.Command("/usr/bin/say", "-v", "Anna", "-o", audio, "Guten Morgen. Heute lernen wir zusammen Deutsch. Das Wetter ist schön.").CombinedOutput(); e != nil {
		t.Fatalf("say: %s %v", out, e)
	}
	p := podcastService{whisper: "/opt/homebrew/bin/whisper", ffmpeg: "/opt/homebrew/bin/ffmpeg", ffprobe: "/opt/homebrew/bin/ffprobe", modelDir: filepath.Join(os.Getenv("HOME"), ".cache", "whisper")}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	segments, e := p.transcribe(ctx, audio, dir, "de")
	if e != nil {
		t.Fatal(e)
	}
	text := ""
	for _, s := range segments {
		text += s.Text + " "
	}
	t.Logf("real local transcript: %s", text)
	if !strings.Contains(strings.ToLower(text), "deutsch") {
		t.Fatalf("missing spoken content: %s", text)
	}
	// Exercise the durable URL->fetch->real recognition->personal Responses path.
	// Only HTTP wire events are synthetic: no real provider credentials or paid call.
	t.Setenv("PROVIDER_KEY_FILE", filepath.Join(t.TempDir(), "key"))
	os.WriteFile(os.Getenv("PROVIDER_KEY_FILE"), []byte(strings.Repeat("k", 32)), 0600)
	cfg := &serverConfig{authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json"), httpClient: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		body := `{"models":[{"slug":"offered","display_name":"Synthetic","visibility":"list"}]}`
		if strings.HasSuffix(r.URL.Path, "responses") {
			body = accountTranslationSSE(`{"text":"Синтетический тест перевода."}`, true, "response.completed")
		}
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(body))}, nil
	})}}
	if _, e := newHandler(cfg); e != nil {
		t.Fatal(e)
	}
	if e := cfg.provider.save("owner", providerCredential{AccessToken: "synthetic-owner", Expires: time.Now().Add(time.Hour)}); e != nil {
		t.Fatal(e)
	}
	store, e := openPodcastStore(filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json"))
	if e != nil {
		t.Fatal(e)
	}
	p.cfg = cfg
	p.store = store
	fixture, e := os.ReadFile(audio)
	if e != nil {
		t.Fatal(e)
	}
	fixtureFetcher := podcastFixtureFetcher(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/episode":
			w.Header().Set("Content-Type", "text/html")
			w.Write([]byte(`<audio src="/speech.wav"></audio>`))
		case "/feed":
			w.Header().Set("Content-Type", "application/rss+xml")
			w.Write([]byte(`<rss><channel><title>Real speech fixture</title><item><guid>real-speech</guid><title>German lesson</title><enclosure type="audio/wav" url="/speech.wav"/></item></channel></rss>`))
		case "/speech.wav":
			w.Header().Set("Content-Type", "audio/aiff")
			w.Write(fixture)
		default:
			http.NotFound(w, r)
		}
	})
	found, e := fixtureFetcher.discover(ctx, "http://fixture.example/feed")
	if e != nil || len(found.Episodes) != 1 {
		t.Fatalf("real RSS discovery: %+v %v", found, e)
	}
	t.Logf("real HTTP RSS fixture discovered %d episode without AI enqueue", len(found.Episodes))
	p.fetchAudio = fixtureFetcher.fetch
	if _, e = store.create("owner", "http://fixture.example/episode", "de", time.Now()); e != nil {
		t.Fatal(e)
	}
	job, e := store.claim(time.Now())
	if e != nil {
		t.Fatal(e)
	}
	p.process(ctx, job)
	jobs, e := store.list("owner")
	if e != nil || len(jobs) != 1 || jobs[0].State != "completed" || len(jobs[0].Segments) == 0 || jobs[0].Segments[0].Translation == "" {
		t.Fatalf("pipeline failed: %+v %v", jobs, e)
	}
	t.Logf("durable pipeline: %s, %d segments, progress %d", jobs[0].State, len(jobs[0].Segments), jobs[0].Progress)
}

func TestPodcastFetchBoundsAndRedirectPolicy(t *testing.T) {
	u, _ := url.Parse("https://example.com/a.mp3")
	for _, tc := range []struct {
		name, mime, body string
		length           int64
		status           int
		ok               bool
	}{
		{"audio", "audio/mpeg", "real bytes", 10, 200, true},
		{"HTML", "text/html", "<html>login</html>", 18, 200, false},
		{"declared oversized", "audio/mpeg", "", podcastMaxBytes + 1, 200, false},
		{"empty", "audio/mpeg", "", 0, 200, false},
		{"HTTP error", "audio/mpeg", "", 0, 403, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			client := &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
				if r.Header.Get("Authorization") != "" || r.Header.Get("Cookie") != "" {
					t.Fatal("secret forwarded")
				}
				return &http.Response{StatusCode: tc.status, Header: http.Header{"Content-Type": []string{tc.mime}}, ContentLength: tc.length, Body: io.NopCloser(strings.NewReader(tc.body))}, nil
			})}
			e := podcastFetchHTTP(context.Background(), u, filepath.Join(t.TempDir(), "audio"), client)
			if (e == nil) != tc.ok {
				t.Fatalf("fetch: %v", e)
			}
		})
	}
	client := (podcastFetcher{}).client()
	for _, raw := range []string{"http://127.0.0.1/a.mp3", "https://example.com/a.mp3?secret=1"} {
		u, _ := url.Parse(raw)
		if client.CheckRedirect(&http.Request{URL: u}, []*http.Request{{}}) == nil {
			t.Fatalf("redirect accepted %s", raw)
		}
	}
	if client.Transport.(*http.Transport).Proxy != nil {
		t.Fatal("environment proxy enabled")
	}
}
func TestPodcastBudgetsPersistAcrossReopen(t *testing.T) {
	path := filepath.Join(t.TempDir(), "jobs.json")
	s, _ := openPodcastStore(path)
	now := time.Now()
	for i := 0; i < 4; i++ {
		j, e := s.create("owner", "https://example.com/a.mp3", "de", now)
		if e != nil {
			t.Fatal(e)
		}
		if _, e = s.mutate("owner", j.ID, "cancel", now); e != nil {
			t.Fatal(e)
		}
	}
	s, _ = openPodcastStore(path)
	if _, e := s.create("owner", "https://example.com/a.mp3", "de", now); e != errPodcastLimit {
		t.Fatalf("budget %v", e)
	}
	if _, e := s.create("other", "https://example.com/a.mp3", "de", now); e != nil {
		t.Fatal("owner budget affected another owner", e)
	}
}

func TestPodcastDNSMixedAnswersDenied(t *testing.T) {
	c := podcastFetcher{lookup: func(context.Context, string) ([]net.IPAddr, error) {
		return []net.IPAddr{{IP: net.ParseIP("93.184.216.34")}, {IP: net.ParseIP("10.0.0.2")}}, nil
	}}
	u, _ := url.Parse("https://example.com/a.mp3")
	if _, err := c.addresses(context.Background(), u.Hostname()); err == nil {
		t.Fatal("mixed DNS accepted")
	}
}
