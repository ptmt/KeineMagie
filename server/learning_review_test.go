package main

import (
	"encoding/json"
	"net/http"
	"path/filepath"
	"testing"
	"time"
)

func TestLearningReviewPermalinkRejectsBrowserBearer(t *testing.T) {
	cfg, h, token, _, j := learningFixture(t)
	session, e := cfg.auth.store.lookup(token, time.Now())
	if e != nil {
		t.Fatal(e)
	}
	browser, e := cfg.auth.store.createBrowser(token, session.UserID, time.Now())
	if e != nil {
		t.Fatal(e)
	}
	path := "/v1/podcasts/episodes/title-" + sessionHash(j.ID)[:12]
	if w := authCall(h, http.MethodGet, path, "", browser); w.Code != 401 {
		t.Fatalf("browser bearer bypass: %d %s", w.Code, w.Body.String())
	}
}

func TestLearningReviewTranslationProgressPreservesTranscriptIdentity(t *testing.T) {
	cfg, h, token, _, j := learningFixture(t)
	path := "/v1/learning/episodes/" + j.ID + "/analysis"
	var before, after learningAnalysisView
	if e := json.Unmarshal(authCall(h, "GET", path, "", token).Body.Bytes(), &before); e != nil {
		t.Fatal(e)
	}
	store, e := openPodcastStore(filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json"))
	if e != nil {
		t.Fatal(e)
	}
	e = store.lock.locked(func() error {
		d, e := store.read()
		if e != nil {
			return e
		}
		for i := range d.Jobs {
			if d.Jobs[i].ID == j.ID {
				d.Jobs[i].Segments[0].Translation = "Neue Übersetzung"
			}
		}
		return store.write(d)
	})
	if e != nil {
		t.Fatal(e)
	}
	if e = json.Unmarshal(authCall(h, "GET", path, "", token).Body.Bytes(), &after); e != nil {
		t.Fatal(e)
	}
	if before.TranscriptHash != after.TranscriptHash {
		t.Fatal("translation progress invalidated the source transcript and durable analysis plan")
	}
}
