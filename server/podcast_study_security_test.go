package main

import (
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestPodcastStudyRejectsSpoofingAndConcurrentRetries(t *testing.T) {
	cfg, h, token, _, j := groupFixture(t)
	path := "/v1/learning/episodes/" + j.ID + "/studied"
	for _, body := range []string{`{"studied_at":"2026-01-01T00:00:00Z"}`, `{"owner":"other"}`} {
		if w := authCall(h, "PUT", path, body, token); w.Code != 400 {
			t.Fatalf("client forged study fields: %d", w.Code)
		}
	}
	request := httptest.NewRequest("PUT", path, strings.NewReader(`{}`))
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("X-Passage-Owner", "other")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, request)
	if w.Code != 403 {
		t.Fatal("expected owner mismatch", w.Code)
	}
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if w := authCall(h, "PUT", path, `{}`, token); w.Code != 200 {
				t.Errorf("concurrent study: %d", w.Code)
			}
		}()
	}
	wg.Wait()
	if err := cfg.learningStore(j.Owner).transaction(func(d *learningData) error {
		if len(d.StudiedEpisodes) != 1 {
			t.Error("duplicates")
		}
		return nil
	}, false); err != nil {
		t.Fatal(err)
	}
	at := time.Now().UTC()
	start := time.Date(at.Year(), at.Month(), at.Day(), 0, 0, 0, 0, time.UTC)
	if got := cfg.activityWeek(j.Owner, start, time.UTC); got.Days[0].Counts["podcasts"] != 1 {
		t.Fatal("duplicate activity")
	}
	// Fail closed on unreadable owner store, never acknowledge unsaved completion.
	if err := os.WriteFile(cfg.learningStore(j.Owner).lock.path, []byte("broken"), 0600); err != nil {
		t.Fatal(err)
	}
	if w := authCall(h, "PUT", path, `{}`, token); w.Code != 503 {
		t.Fatal("unreadable store acknowledged", w.Code)
	}
	if got := cfg.activityWeek(j.Owner, start, time.UTC); got.Sources["podcasts"] != "unavailable" || got.Days[0].Coverage != "partial" {
		t.Fatal("failure became verified zero")
	}
}
