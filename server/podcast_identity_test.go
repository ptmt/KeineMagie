package main

import (
	"context"
	"net/http"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func TestPodcastExistingCompletedPreferred(t *testing.T) {
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	now := time.Now()
	j, _ := s.create("owner", "https://example.com/a.mp3", "de", now)
	d, _ := s.read()
	complete := d.Jobs[0]
	complete.ID = "completed-history"
	complete.State = "completed"
	d.Jobs = append(d.Jobs, complete)
	if e := s.write(d); e != nil {
		t.Fatal(e)
	}
	got, e := s.create("owner", j.URL, "de", now)
	if e != nil || got.ID != complete.ID {
		t.Fatal("completed preparation must win over obsolete queued duplicate", e)
	}
}

func TestPodcastHistoricalSameSourceReconciliation(t *testing.T) {
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	now := time.Now()
	old, e := s.create("owner", "https://example.com/page", "de", now)
	if e != nil {
		t.Fatal(e)
	}
	same, e := s.createEpisode("owner", "https://example.com/audio.mp3", "de", "", "", "https://example.com/page", now)
	if e != nil || same.ID != old.ID || same.URL != "https://example.com/audio.mp3" {
		t.Fatal("same known page not reconciled", e)
	}
	unrelated, e := s.createEpisode("owner", "https://example.com/other.mp3", "de", "", "", "https://example.com/other-page", now)
	if e != nil || unrelated.ID == old.ID {
		t.Fatal("unrelated source guessed", e)
	}
}

func TestPodcastDirectMediaIdentityNeedsNoDiscovery(t *testing.T) {
	f := podcastFixtureFetcher(t, func(w http.ResponseWriter, r *http.Request) {
		t.Error("direct audio fetched during identity discovery")
		http.Error(w, "offline", 503)
	})
	p := podcastService{sourceFetcher: &f}
	got, e := p.resolveImport(context.Background(), "https://example.com/audio.mp3")
	if e != nil || got != "https://example.com/audio.mp3" {
		t.Fatal("direct audio identity unavailable", e)
	}
}

func TestPodcastClaimRetainsDuplicatesWithoutRerun(t *testing.T) {
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	now := time.Now()
	j, e := s.create("owner", "https://example.com/a.mp3", "de", now)
	if e != nil {
		t.Fatal(e)
	}
	d, e := s.read()
	if e != nil {
		t.Fatal(e)
	}
	duplicate := d.Jobs[0]
	duplicate.ID = "historical-duplicate"
	d.Jobs = append(d.Jobs, duplicate)
	if e = s.write(d); e != nil {
		t.Fatal(e)
	}
	first, e := s.claim(now)
	if e != nil || first.ID != j.ID {
		t.Fatal("wrong initial claim", e)
	}
	if next, e := s.claim(now); e != nil || next.ID != "" {
		t.Fatal("duplicate claimed during canonical processing", e)
	}
	first.State = "failed"
	if e = s.update(first); e != nil {
		t.Fatal(e)
	}
	if next, e := s.claim(now); e != nil || next.ID != "" {
		t.Fatal("duplicate re-ran after canonical failure", e)
	}
	jobs, e := s.list("owner")
	if e != nil || len(jobs) != 2 {
		t.Fatal("historical duplicate deleted", e)
	}
	for _, job := range jobs {
		if job.ID == duplicate.ID && (job.State != "failed" || job.Attempts != 0 || job.Error == "") {
			t.Fatal("duplicate must be terminal and explained, without an attempt")
		}
	}
}

func TestPodcastExplicitDeleteAllowsReimport(t *testing.T) {
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	now := time.Now()
	j, e := s.create("owner", "https://example.com/a.mp3", "de", now)
	if e != nil {
		t.Fatal(e)
	}
	if _, e = s.mutate("owner", j.ID, "cancel", now); e != nil {
		t.Fatal(e)
	}
	if _, e = s.mutate("owner", j.ID, "delete", now); e != nil {
		t.Fatal(e)
	}
	again, e := s.create("owner", j.URL, "de", now)
	if e != nil || again.ID == j.ID {
		t.Fatal("explicit deletion should permit fresh import", e)
	}
}

func TestPodcastLegacyHTMLMatchesEnclosure(t *testing.T) {
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	fetcher := podcastFixtureFetcher(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		w.Write([]byte(`<audio src="https://example.com/audio.mp3"></audio>`))
	})
	p := &podcastService{store: s, sourceFetcher: &fetcher}
	raw, e := p.resolveImport(context.Background(), "http://example.com/page")
	if e != nil {
		t.Fatal(e)
	}
	j, _ := s.createEpisode("owner", raw, "de", "", "", "https://example.com/page", time.Now())
	other, e := s.create("owner", "https://example.com/audio.mp3", "de", time.Now())
	if e != nil || other.ID != j.ID {
		t.Fatal("page and enclosure duplicated")
	}
}

func TestPodcastCanceledRetryIdentity(t *testing.T) {
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	now := time.Now()
	j, _ := s.create("owner", "https://example.com/a.mp3", "de", now)
	s.mutate("owner", j.ID, "cancel", now)
	repeat, e := s.create("owner", j.URL, "de", now)
	if e != nil || repeat.ID != j.ID || repeat.State != "canceled" {
		t.Fatal("import implicitly retried")
	}
	retry, e := s.mutate("owner", j.ID, "retry", now)
	if e != nil || retry.ID != j.ID || retry.State != "queued" {
		t.Fatalf("explicit retry: %v", e)
	}
}

func TestPodcastFeedIdentityAndEpisodeState(t *testing.T) {
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	now := time.Now()
	sub, e := s.saveSubscription("owner", "", podcastDiscovery{URL: "https://example.com/feed", Episodes: []podcastEpisode{{ID: "one", Title: "Real title", URL: "https://example.com/a.mp3"}, {ID: "two", Title: "Other episode", URL: "https://example.com/a.mp3"}}}, now)
	if e != nil {
		t.Fatal(e)
	}
	j, e := s.createEpisode("owner", "https://ignored.example/x", "de", sub.ID, "one", "", now)
	if e != nil || j.Title != "Real title" || j.URL != "https://example.com/a.mp3" {
		t.Fatal("unverified episode metadata")
	}
	if _, e = s.createEpisode("other", "", "de", sub.ID, "one", "", now); e != errPodcastNotFound {
		t.Fatal("foreign subscription accepted")
	}
	other, e := s.createEpisode("owner", "", "de", sub.ID, "two", "", now)
	if e != nil || other.ID == j.ID {
		t.Fatal("distinct GUIDs collapsed")
	}
	subs, _ := s.subscriptions("owner")
	if subs[0].Episodes[0].Preparation == nil || subs[0].Episodes[0].Preparation.ID != j.ID {
		t.Fatal("episode missing preparation state")
	}
}

func TestPodcastImportIdentityConcurrentDurable(t *testing.T) {
	path := filepath.Join(t.TempDir(), "jobs.json")
	s, _ := openPodcastStore(path)
	var wg sync.WaitGroup
	ids := make(chan string, 20)
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			other, _ := openPodcastStore(path)
			j, e := other.create("owner", "https://example.com/audio.mp3", "de", time.Now())
			if e != nil {
				t.Error(e)
				return
			}
			ids <- j.ID
		}()
	}
	wg.Wait()
	close(ids)
	id := ""
	for got := range ids {
		if id != "" && id != got {
			t.Error("duplicate job")
		}
		id = got
	}
	j, e := s.claim(time.Now())
	if e != nil {
		t.Fatal(e)
	}
	j.State = "completed"
	if e = s.update(j); e != nil {
		t.Fatal(e)
	}
	reopened, _ := openPodcastStore(path)
	again, e := reopened.create("owner", j.URL, "de", time.Now())
	if e != nil || again.ID != id || again.State != "completed" {
		t.Fatalf("repeat: %s %v", again.State, e)
	}
	d, _ := reopened.read()
	if len(d.Jobs) != 1 || d.Budgets[sessionHash("owner")].Attempts != 1 {
		t.Fatal("duplicate reservation")
	}
}
