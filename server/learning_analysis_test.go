package main

import (
	"encoding/json"
	"io"
	"net/http"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestLearningAnalysisExplicitPersonalCheckpointAndGrounding(t *testing.T) {
	cfg, h, token, other, j := learningFixture(t)
	calls := 0
	result := `{"narrative":[{"text":"Gemeinsames Lernen.","citations":[{"segment_id":0,"quote":"lernen gemeinsam"}]}],"topics":[{"title":"Lernen","key_points":[{"text":"Zusammen lernen.","citations":[{"segment_id":0,"quote":"lernen gemeinsam"}]}]}],"recommendations":[]}`
	cfg.provider.client = &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		calls++
		if r.URL.Path == "/v1/models" {
			return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"models":[{"slug":"gpt-4o","visibility":"list"}]}`)), Header: http.Header{}}, nil
		}
		var req map[string]any
		json.NewDecoder(r.Body).Decode(&req)
		if req["stream"] != true {
			t.Error("not streaming")
		}
		snapshot, _ := json.Marshal(map[string]any{"type": "response.completed", "response": map[string]any{"status": "completed", "output": []any{map[string]any{"type": "message", "content": []any{map[string]any{"type": "output_text", "text": result}}}}}})
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader("data: " + string(snapshot) + "\n\n")), Header: http.Header{}}, nil
	})}
	cfg.provider.key = make([]byte, 32)
	session, _ := cfg.auth.store.lookup(token, time.Now())
	if e := cfg.provider.save(session.UserID, providerCredential{AccessToken: "personal-test", Expires: time.Now().Add(time.Hour)}); e != nil {
		t.Fatal(e)
	}
	path := "/v1/learning/episodes/" + j.ID + "/analysis"
	w := authCall(h, "GET", path, "", token)
	if w.Code != 200 || calls != 0 {
		t.Fatalf("GET %d %s calls %d", w.Code, w.Body.String(), calls)
	}
	if w = authCall(h, "GET", path, "", other); w.Code != 404 {
		t.Fatal("owner leak", w.Code)
	}
	w = authCall(h, "POST", path, `{}`, token)
	if w.Code != 200 {
		t.Fatalf("generation %d %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), `"start":2`) || !strings.Contains(w.Body.String(), `"profile_required":true`) {
		t.Fatal(w.Body.String())
	}
	before := calls
	body := `{"job_id":"` + j.ID + `","segment_id":0,"quote":"lernen gemeinsam","term":"lernen","kind":"word","status":"learning"}`
	if w = authCall(h, "POST", "/v1/learning/vocabulary", body, token); w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
	w = authCall(h, "GET", path, "", token)
	if strings.Contains(w.Body.String(), `"state":"completed"`) {
		t.Fatal("stale progress cache")
	}
	w = authCall(h, "POST", path, `{}`, token)
	if w.Code != 200 || calls <= before {
		t.Fatal("progress did not invalidate", w.Code, w.Body.String())
	}
	before = calls
	w = authCall(h, "POST", path, `{}`, token)
	if w.Code != 200 || calls != before {
		t.Fatal("cache replay", w.Code, calls, before)
	}
	authCall(h, "PUT", "/v1/learning/profiles/de", `{"cefr":"B1"}`, token)
	store, _ := openPodcastStore(filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json"))
	if e := store.lock.locked(func() error {
		d, e := store.read()
		if e != nil {
			return e
		}
		for i := range d.Jobs {
			if d.Jobs[i].ID == j.ID {
				d.Jobs[i].Segments[0].Text += " Neue Information."
			}
		}
		return store.write(d)
	}); e != nil {
		t.Fatal(e)
	}
	w = authCall(h, "GET", path, "", token)
	var changed learningAnalysisView
	json.Unmarshal(w.Body.Bytes(), &changed)
	if changed.TranscriptHash == learningDigest(j.Segments) || changed.State == "completed" {
		t.Fatal("stale transcript cache")
	}
	result = strings.ReplaceAll(result, "lernen gemeinsam", "invented quotation")
	w = authCall(h, "POST", path, `{}`, token)
	if w.Code != 502 {
		t.Fatalf("fabricated quote accepted: %d %s", w.Code, w.Body.String())
	}
	w = authCall(h, "GET", path, "", token)
	if strings.Contains(w.Body.String(), `"state":"completed"`) {
		t.Fatal("invalid output ready")
	}
}
