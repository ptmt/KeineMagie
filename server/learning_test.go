package main

import (
	"encoding/json"
	"net/http"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func learningFixture(t *testing.T) (*serverConfig, http.Handler, string, string, podcastJob) {
	t.Helper()
	t.Setenv("PODCAST_LOCAL_WORKER", "")
	cfg := &serverConfig{authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json")}
	h, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	token, s, e := cfg.auth.store.create("learner", time.Now())
	if e != nil {
		t.Fatal(e)
	}
	other, _, _ := cfg.auth.store.create("other-learner", time.Now())
	store, e := openPodcastStore(filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json"))
	if e != nil {
		t.Fatal(e)
	}
	j, e := store.create(s.UserID, "https://example.com/learning.mp3", "de", time.Now())
	if e != nil {
		t.Fatal(e)
	}
	j, e = store.claim(time.Now())
	if e != nil {
		t.Fatal(e)
	}
	j.State = "completed"
	j.Segments = []podcastSegment{{Start: 2, End: 9, Text: "Wir drücken die Daumen und lernen gemeinsam.", Translation: "Держим кулаки и учимся вместе."}}
	if e = store.update(j); e != nil {
		t.Fatal(e)
	}
	return cfg, h, token, other, j
}
func TestLearningVocabularyGroundingAndProgress(t *testing.T) {
	_, h, token, other, j := learningFixture(t)
	body := `{"job_id":"` + j.ID + `","segment_id":0,"quote":"drücken die Daumen","term":"Daumen","kind":"idiom","translation":"держать кулаки","notes":"context","favorite":true,"status":"learning"}`
	w := authCall(h, "POST", "/v1/learning/vocabulary", body, token)
	if w.Code != 201 {
		t.Fatalf("save: %d %s", w.Code, w.Body.String())
	}
	var v learningVocabulary
	json.Unmarshal(w.Body.Bytes(), &v)
	if v.Start != 2 || v.End != 9 || v.Language != "de" {
		t.Fatalf("citation %+v", v)
	}
	if w = authCall(h, "PATCH", "/v1/learning/vocabulary/"+v.ID, `{"status":"known"}`, other); w.Code != 404 {
		t.Fatal("foreign write", w.Code)
	}
	w = authCall(h, "PATCH", "/v1/learning/vocabulary/"+v.ID, `{"status":"known","notes":"learned"}`, token)
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	json.Unmarshal(w.Body.Bytes(), &v)
	if len(v.History) != 2 {
		t.Fatal("missing action history")
	}
	w = authCall(h, "GET", "/v1/learning/profiles/de", "", token)
	var p learningProfile
	json.Unmarshal(w.Body.Bytes(), &p)
	if p.CEFR != "unknown" || p.Progress.Known != 1 || p.Progress.Learning != 0 || p.Progress.Favorites != 1 {
		t.Fatalf("fabricated progress: %+v", p)
	}
	for _, bad := range []string{strings.Replace(body, "drücken die Daumen", "fabricated quote", 1), strings.Replace(body, `"segment_id":0`, `"segment_id":3`, 1)} {
		if w = authCall(h, "POST", "/v1/learning/vocabulary", bad, token); w.Code != 400 {
			t.Fatal("accepted fabrication", w.Code)
		}
	}
	if w = authCall(h, "POST", "/v1/learning/vocabulary", body, other); w.Code != 404 {
		t.Fatal("foreign source", w.Code)
	}
	if w = authCall(h, "DELETE", "/v1/learning/vocabulary/"+v.ID, "", token); w.Code != 204 {
		t.Fatal(w.Code)
	}
}

func TestLearningProfileDurableExplicitHistory(t *testing.T) {
	cfg, h, token, other, _ := learningFixture(t)
	w := authCall(h, "GET", "/v1/learning/profiles/de", "", token)
	if w.Code != 200 {
		t.Fatalf("missing profile: %d %s", w.Code, w.Body.String())
	}
	var p learningProfile
	if e := json.Unmarshal(w.Body.Bytes(), &p); e != nil {
		t.Fatal(e)
	}
	if p.CEFR != "unknown" || len(p.SelfAssessments) != 0 {
		t.Fatalf("fabricated assessment: %+v", p)
	}
	for _, level := range []string{"A2", "B1"} {
		w = authCall(h, "PUT", "/v1/learning/profiles/de", `{"cefr":"`+level+`"}`, token)
		if w.Code != 200 {
			t.Fatal(w.Code, w.Body.String())
		}
	}
	reopened, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	w = authCall(reopened, "GET", "/v1/learning/profiles/de", "", token)
	json.Unmarshal(w.Body.Bytes(), &p)
	if p.CEFR != "B1" || len(p.SelfAssessments) != 2 || p.SelfAssessments[0].AssessedAt.IsZero() {
		t.Fatalf("lost history: %+v", p)
	}
	w = authCall(h, "GET", "/v1/learning/profiles/de", "", other)
	var q learningProfile
	json.Unmarshal(w.Body.Bytes(), &q)
	if q.CEFR != "unknown" {
		t.Fatal("owner leak")
	}
	if w = authCall(h, "PUT", "/v1/learning/profiles/de", `{"cefr":"D1"}`, token); w.Code != 400 {
		t.Fatal("accepted invalid CEFR", w.Code)
	}
}
