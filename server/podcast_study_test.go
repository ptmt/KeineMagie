package main

import (
	"encoding/json"
	"os"
	"testing"
	"time"
)

func TestPodcastStudyHTTPDurableExplicitDedupDelete(t *testing.T) {
	cfg, h, token, other, j := groupFixture(t)
	path := "/v1/learning/episodes/" + j.ID + "/studied"
	// Opening and starring must not fabricate a study completion.
	starGroup(t, h, token, j.ID, 0, true)
	at := time.Now().UTC()
	start := time.Date(at.Year(), at.Month(), at.Day(), 0, 0, 0, 0, time.UTC)
	if got := cfg.activityWeek(j.Owner, start, time.UTC); got.Days[0].KnownCount != 0 {
		t.Fatal("implicit completion")
	}
	if w := authCall(h, "PUT", path, `{}`, other); w.Code != 404 {
		t.Fatalf("foreign owner %d", w.Code)
	}
	first := authCall(h, "PUT", path, `{}`, token)
	if first.Code != 200 {
		t.Fatalf("explicit study unavailable: %d %s", first.Code, first.Body.String())
	}
	var initial map[string]any
	if err := json.Unmarshal(first.Body.Bytes(), &initial); err != nil {
		t.Fatal(err)
	}
	if initial["studied_at"] == nil {
		t.Fatal("missing saved date")
	}
	if path := os.Getenv("PODCAST_STUDY_WIRE_PATH"); path != "" {
		if err := os.WriteFile(path, first.Body.Bytes(), 0600); err != nil {
			t.Fatal(err)
		}
	}
	second := authCall(h, "PUT", path, `{}`, token)
	if second.Code != 200 || second.Body.String() != first.Body.String() {
		t.Fatal("retry changed completion date or revision")
	}
	reopened := &serverConfig{historyPath: cfg.historyPath}
	if got := reopened.activityWeek(j.Owner, start, time.UTC); got.Days[0].KnownCount != 1 || got.Days[0].Counts["podcasts"] != 1 {
		t.Fatalf("restart lost completion: %+v", got)
	}
	read := authCall(h, "GET", "/v1/learning/episodes/"+j.ID+"/passage-groups", "", token)
	var saved map[string]any
	_ = json.Unmarshal(read.Body.Bytes(), &saved)
	if saved["studied_at"] != initial["studied_at"] {
		t.Fatal("readback lost completion")
	}
	if w := authCall(h, "DELETE", "/v1/podcasts/"+j.ID, "", token); w.Code != 204 {
		t.Fatal(w.Code)
	}
	if got := reopened.activityWeek(j.Owner, start, time.UTC); got.Days[0].KnownCount != 0 {
		t.Fatal("deleted episode retained study activity")
	}
	if w := authCall(h, "PUT", path, `{}`, token); w.Code != 404 {
		t.Fatal("resurrected deleted source")
	}
}
