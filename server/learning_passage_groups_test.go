package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"sync"
	"testing"
)

func groupFixture(t *testing.T) (*serverConfig, http.Handler, string, string, podcastJob) {
	cfg, h, token, other, j := learningFixture(t)
	s, _ := openPodcastStore(filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json"))
	if err := s.lock.locked(func() error {
		d, e := s.read()
		if e != nil {
			return e
		}
		for i := range d.Jobs {
			if d.Jobs[i].ID == j.ID {
				for k := 1; k < 6; k++ {
					d.Jobs[i].Segments = append(d.Jobs[i].Segments, podcastSegment{Start: float64(100 - k), End: float64(101 - k), Text: fmt.Sprintf("Original %d.", k)})
				}
				j = storedPodcast(d.Jobs[i])
			}
		}
		return s.write(d)
	}); err != nil {
		t.Fatal(err)
	}
	return cfg, h, token, other, j
}
func readGroups(t *testing.T, h http.Handler, token, id string) learningPassageGroups {
	t.Helper()
	w := authCall(h, "GET", "/v1/learning/episodes/"+id+"/passage-groups", "", token)
	if w.Code != 200 {
		t.Fatalf("GET groups %d", w.Code)
	}
	var out learningPassageGroups
	if e := json.Unmarshal(w.Body.Bytes(), &out); e != nil {
		t.Fatal(e)
	}
	return out
}
func starGroup(t *testing.T, h http.Handler, token, id string, index int, on bool) {
	t.Helper()
	w := authCall(h, "PUT", fmt.Sprintf("/v1/learning/episodes/%s/passages/%d", id, index), fmt.Sprintf(`{"favorite":%t}`, on), token)
	if w.Code != 200 {
		t.Fatalf("star %d: %d", index, w.Code)
	}
}
func TestPassageGroupsRunsBridgeSplitReplayConcurrent(t *testing.T) {
	cfg, h, token, other, j := groupFixture(t)
	original, _ := json.Marshal(j.Segments)
	check := func(want [][]int) learningPassageGroups {
		out := readGroups(t, h, token, j.ID)
		got := [][]int{}
		for _, g := range out.Groups {
			got = append(got, g.SegmentIDs)
		}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("groups %v want %v", got, want)
		}
		return out
	}
	starGroup(t, h, token, j.ID, 0, true)
	single := check([][]int{{0}})
	starGroup(t, h, token, j.ID, 2, true)
	check([][]int{{0}, {2}})
	starGroup(t, h, token, j.ID, 1, true)
	merged := check([][]int{{0, 1, 2}})
	if merged.Groups[0].Start != 2 || merged.Groups[0].End != 99 {
		t.Fatal("timestamp sorting instead of original order")
	}
	starGroup(t, h, token, j.ID, 1, true)
	retry := check([][]int{{0, 1, 2}})
	if retry.Revision != merged.Revision || retry.Groups[0].ID != merged.Groups[0].ID {
		t.Fatal("retry changed identity/revision")
	}
	starGroup(t, h, token, j.ID, 1, false)
	split := check([][]int{{0}, {2}})
	if split.Groups[0].ID != single.Groups[0].ID {
		t.Fatal("membership identity not deterministic")
	}
	starGroup(t, h, token, j.ID, 0, false)
	check([][]int{{2}})
	starGroup(t, h, token, j.ID, 2, false)
	check([][]int{})
	var wg sync.WaitGroup
	for _, i := range []int{5, 3, 4, 3, 5} {
		wg.Add(1)
		go func(i int) { defer wg.Done(); starGroup(t, h, token, j.ID, i, true) }(i)
	}
	wg.Wait()
	check([][]int{{3, 4, 5}})
	if w := authCall(h, "GET", "/v1/learning/episodes/"+j.ID+"/passage-groups", "", other); w.Code != 404 {
		t.Fatal("cross owner", w.Code)
	}
	latest, e := cfg.learningJob(j.Owner, j.ID)
	if e != nil {
		t.Fatal(e)
	}
	after, _ := json.Marshal(latest.Segments)
	if string(after) != string(original) {
		t.Fatal("transcript changed")
	}
}
func TestPassageGroupsDeletionRemovesRelationships(t *testing.T) {
	cfg, h, token, _, j := groupFixture(t)
	starGroup(t, h, token, j.ID, 0, true)
	if w := authCall(h, "DELETE", "/v1/podcasts/"+j.ID, "", token); w.Code != 204 {
		t.Fatal(w.Code)
	}
	if e := cfg.learningStore(j.Owner).transaction(func(d *learningData) error {
		if len(d.Passages) != 0 || len(d.PassageGroups) != 0 {
			t.Error("orphan relationships remain")
		}
		return nil
	}, false); e != nil {
		t.Fatal(e)
	}
	if w := authCall(h, "PUT", "/v1/learning/episodes/"+j.ID+"/passages/0", `{"favorite":true}`, token); w.Code != 404 {
		t.Fatal("resurrected deleted source")
	}
}
func TestPassageGroupsCoachUsesOneSpan(t *testing.T) {
	cfg, h, token, _, j := groupFixture(t)
	starGroup(t, h, token, j.ID, 0, true)
	starGroup(t, h, token, j.ID, 1, true)
	sources, e := cfg.coachSources(j.Owner)
	if e != nil {
		t.Fatal(e)
	}
	if len(sources) != 1 || sources[0].Text != j.Segments[0].Text+" "+j.Segments[1].Text {
		t.Fatalf("Coach did not consume one span: %d sources", len(sources))
	}
	turn := coachTurn{Language: j.SourceLanguage, Result: &coachResult{Kind: "cloze", Prompt: "___", Target: "grammar.case", SourceID: sources[0].ID, Quote: sources[0].Text}}
	resolved, e := cfg.coachAssessmentSource(j.Owner, turn)
	if e != nil || resolved.Text != sources[0].Text {
		t.Fatal("group provenance did not resolve", e)
	}
	if _, e = cfg.coachAssessmentSource("foreign-owner", turn); e == nil {
		t.Fatal("group assessment crossed owner")
	}
	starGroup(t, h, token, j.ID, 1, false)
	if _, e = cfg.coachAssessmentSource(j.Owner, turn); e == nil {
		t.Fatal("changed group reinterpreted old exercise")
	}
}
func TestPassageGroupsLegacyMigrationAndFailedPersistence(t *testing.T) {
	cfg, h, token, _, j := groupFixture(t)
	s := cfg.learningStore(j.Owner)
	if e := s.transaction(func(d *learningData) error {
		d.Passages = []learningPassage{{j.ID, 2, j.Segments[2].Text}, {j.ID, 0, j.Segments[0].Text}, {j.ID, 1, j.Segments[1].Text}}
		return nil
	}, true); e != nil {
		t.Fatal(e)
	}
	first := readGroups(t, h, token, j.ID)
	second := readGroups(t, h, token, j.ID)
	if len(first.Groups) != 1 || first.Revision != second.Revision {
		t.Fatal("migration not idempotent")
	}
	// The lock remains usable, but the JSON target cannot be atomically replaced.
	if e := os.Remove(s.lock.path); e != nil {
		t.Fatal(e)
	}
	if e := os.Mkdir(s.lock.path, 0700); e != nil {
		t.Fatal(e)
	}
	w := authCall(h, "PUT", "/v1/learning/episodes/"+j.ID+"/passages/4", `{"favorite":true}`, token)
	if w.Code != 503 {
		t.Fatal("failed persistence acknowledged", w.Code)
	}
}

func TestPassageGroupsDurableSingleton(t *testing.T) {
	cfg, h, token, _, j := learningFixture(t)
	base := "/v1/learning/episodes/" + j.ID
	w := authCall(h, "PUT", base+"/passages/0", `{"favorite":true}`, token)
	if w.Code != 200 {
		t.Fatal(w.Code)
	}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	w = authCall(h, "GET", base+"/passage-groups", "", token)
	if w.Code != 200 {
		t.Fatalf("groups GET: %d", w.Code)
	}
	var out struct {
		Version  int `json:"version"`
		Revision int `json:"revision"`
		Groups   []struct {
			ID         string  `json:"id"`
			SegmentIDs []int   `json:"segment_ids"`
			Start      float64 `json:"start"`
			End        float64 `json:"end"`
		} `json:"groups"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if out.Version != 1 || out.Revision < 1 || len(out.Groups) != 1 || len(out.Groups[0].SegmentIDs) != 1 || out.Groups[0].SegmentIDs[0] != 0 || out.Groups[0].Start != 2 || out.Groups[0].End != 9 {
		t.Fatalf("invalid group: %+v", out)
	}
}
