package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestPodcastCoverageFailureDoesNotBlockIndependentTranscript(t *testing.T) {
	cfg, h, token, _, j := learningFixture(t)
	session, _ := cfg.auth.store.lookup(token, time.Now())
	path := cfg.learningStore(session.UserID).lock.path
	if e := os.MkdirAll(filepath.Dir(path), 0700); e != nil {
		t.Fatal(e)
	}
	if e := os.WriteFile(path, []byte(`invalid`), 0600); e != nil {
		t.Fatal(e)
	}
	for _, url := range []string{"/v1/podcasts", "/v1/podcasts/" + j.ID} {
		w := authCall(h, "GET", url, "", token)
		if w.Code != 200 {
			t.Fatalf("independent transcript blocked %s: %d", url, w.Code)
		}
		var body map[string]any
		json.Unmarshal(w.Body.Bytes(), &body)
		if url == "/v1/podcasts" {
			body = body["items"].([]any)[0].(map[string]any)
		}
		if _, ok := body["coverage"]; ok {
			t.Fatal("unknown coverage shown as known")
		}
	}
}

func TestPassageCoverageUsesExactCurrentSourceAndUniqueMarks(t *testing.T) {
	j := podcastJob{ID: "job", Segments: []podcastSegment{{Text: "First sentence. Second sentence.", Translation: " \n"}, {Text: "Another.", Translation: "Перевод"}}}
	marks := []learningPassage{{JobID: "job", SegmentID: 0, Quote: j.Segments[0].Text}, {JobID: "job", SegmentID: 0, Quote: j.Segments[0].Text}, {JobID: "other", SegmentID: 1, Quote: "Another."}, {JobID: "job", SegmentID: 1, Quote: "stale source"}, {JobID: "job", SegmentID: 99, Quote: "bad"}}
	c := coverageFor(j, marks)
	if c.Recognized != 2 || c.Translated != 1 || c.Favorites != 1 {
		t.Fatalf("wrong counts: %+v", c)
	}
}
