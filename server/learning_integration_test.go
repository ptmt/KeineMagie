package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestLearningLongEpisodeResumesCompleteMapReduce(t *testing.T) {
	cfg, h, token, _, j := learningFixture(t)
	store, _ := openPodcastStore(filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json"))
	j.Segments = nil
	for i := 0; i < 216; i++ {
		j.Segments = append(j.Segments, podcastSegment{Start: float64(i * 10), End: float64(i*10 + 9), Text: fmt.Sprintf("Thema %03d ", i) + strings.Repeat("a", 990)})
	}
	// Fixture has a completed claimed job: replace under the same durable fence.
	if e := store.lock.locked(func() error {
		d, e := store.read()
		if e != nil {
			return e
		}
		for i := range d.Jobs {
			if d.Jobs[i].ID == j.ID {
				d.Jobs[i].Segments = j.Segments
				return store.write(d)
			}
		}
		return errPodcastNotFound
	}); e != nil {
		t.Fatal(e)
	}
	plan, chars, e := learningPlan(j)
	if e != nil || chars < 216000 || len(plan) < 20 {
		t.Fatalf("bad plan %d %d %v", len(plan), chars, e)
	}
	cfg.provider.key = make([]byte, 32)
	s, _ := cfg.auth.store.lookup(token, time.Now())
	if e = cfg.provider.save(s.UserID, providerCredential{AccessToken: "personal", Expires: time.Now().Add(time.Hour)}); e != nil {
		t.Fatal(e)
	}
	calls := 0
	fail := false
	covered := map[int]bool{}
	client := &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		if r.Method == "GET" {
			return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"models":[{"slug":"gpt-4o","visibility":"list"}]}`)), Header: http.Header{}}, nil
		}
		calls++
		if fail {
			return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader("data: {\"type\":\"response.incomplete\"}\n\n")), Header: http.Header{}}, nil
		}
		var wire struct {
			Input []struct {
				Content string `json:"content"`
			} `json:"input"`
		}
		if e := json.NewDecoder(r.Body).Decode(&wire); e != nil {
			t.Fatal(e)
		}
		var in struct {
			Segments []podcastTranslationItem `json:"segments"`
			Children []learningResult         `json:"child_summaries"`
		}
		if e := json.Unmarshal([]byte(wire.Input[0].Content), &in); e != nil {
			t.Fatal(e)
		}
		citations := []learningCitation{}
		if len(in.Segments) > 0 {
			for _, seg := range in.Segments {
				covered[seg.ID] = true
			}
			for _, seg := range in.Segments[:1] {
				citations = append(citations, learningCitation{SegmentID: seg.ID, Quote: seg.Text[:9]})
			}
		} else {
			for _, child := range in.Children {
				citations = append(citations, child.Narrative[0].Citations[0])
			}
		}
		// Provider never returns timestamps; server must reconstruct them.
		bare := []map[string]any{}
		for _, c := range citations {
			bare = append(bare, map[string]any{"segment_id": c.SegmentID, "quote": c.Quote})
		}
		point := map[string]any{"text": "Ausführliche Zusammenfassung des Themas.", "citations": bare}
		result, _ := json.Marshal(map[string]any{"narrative": []any{point}, "topics": []any{map[string]any{"title": "Thema", "key_points": []any{point}}}, "recommendations": []any{}})
		delta, _ := json.Marshal(map[string]any{"type": "response.output_text.delta", "delta": string(result)})
		completed, _ := json.Marshal(map[string]any{"type": "response.completed", "response": map[string]any{"status": "completed", "output": []any{map[string]any{"type": "message", "content": []any{map[string]any{"type": "output_text", "text": string(result)}}}}}})
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader("data: " + string(delta) + "\n\ndata: " + string(completed) + "\n\n")), Header: http.Header{}}, nil
	})}
	cfg.provider.client = client
	path := "/v1/learning/episodes/" + j.ID + "/analysis"
	w := authCall(h, "POST", path, `{}`, token)
	if w.Code != 202 {
		t.Fatal(w.Code, w.Body.String())
	}
	fail = true
	w = authCall(h, "POST", path, `{}`, token)
	if w.Code != 502 {
		t.Fatal(w.Code, w.Body.String())
	}
	// New router/services, same disk. Completed chunk zero must not replay.
	h, e = newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	cfg.provider.key = make([]byte, 32)
	cfg.provider.client = client
	fail = false
	w = authCall(h, "GET", path, "", token)
	var view learningAnalysisView
	json.Unmarshal(w.Body.Bytes(), &view)
	if view.CompletedSteps != 1 || view.Result != nil {
		t.Fatalf("checkpoint lost %+v", view)
	}
	for i := 1; i < len(plan); i++ {
		w = authCall(h, "POST", path, `{}`, token)
		want := 202
		if i == len(plan)-1 {
			want = 200
		}
		if w.Code != want {
			t.Fatalf("step %d: %d %s", i, w.Code, w.Body.String())
		}
	}
	if calls != len(plan)+1 || len(covered) != 216 {
		t.Fatalf("replay/excerpt calls %d expected %d coverage %d", calls, len(plan)+1, len(covered))
	}
	json.Unmarshal(w.Body.Bytes(), &view)
	if view.State != "completed" || view.Result == nil || view.Estimate.Remaining != 0 {
		t.Fatalf("not complete %+v", view)
	}
}
func TestLearningConcurrentProfileUpdatesNoLostHistory(t *testing.T) {
	cfg, _, token, _, _ := learningFixture(t)
	s, _ := cfg.auth.store.lookup(token, time.Now())
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			store := cfg.learningStore(s.UserID)
			if e := store.transaction(func(d *learningData) error {
				p := learningGetProfile(d, "de")
				p.SelfAssessments = append(p.SelfAssessments, learningAssessment{CEFR: "A1", AssessedAt: time.Now()})
				d.Profiles["de"] = p
				return nil
			}, true); e != nil {
				t.Error(e)
			}
		}()
	}
	wg.Wait()
	cfg.learningStore(s.UserID).transaction(func(d *learningData) error {
		if len(d.Profiles["de"].SelfAssessments) != 20 {
			t.Error("lost update")
		}
		return nil
	}, false)
}
func TestLearningBrowserCSRFAndBearerIsolation(t *testing.T) {
	t.Setenv("WEB_ORIGIN", "https://example.com")
	cfg, h, token, _, _ := learningFixture(t)
	s, _ := cfg.auth.store.lookup(token, time.Now())
	browser, e := cfg.auth.store.createBrowser(token, s.UserID, time.Now())
	if e != nil {
		t.Fatal(e)
	}
	for _, tc := range []struct {
		origin, csrf, bearer string
		cookie               bool
		code                 int
	}{{"https://example.com", "", "", true, 403}, {"https://evil.invalid", browserCSRF(browser), "", true, 403}, {"", "", browser, false, 401}, {"https://example.com", browserCSRF(browser), "", true, 200}} {
		r := httptest.NewRequest("PUT", "/v1/learning/profiles/de", strings.NewReader(`{"cefr":"A1"}`))
		r.Header.Set("Origin", tc.origin)
		r.Header.Set("X-CSRF-Token", tc.csrf)
		if tc.cookie {
			r.AddCookie(&http.Cookie{Name: browserCookie, Value: browser})
		}
		if tc.bearer != "" {
			r.Header.Set("Authorization", "Bearer "+tc.bearer)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != tc.code {
			t.Errorf("browser %+v got %d %s", tc, w.Code, w.Body.String())
		}
	}
}
func TestLearningConcurrentGenerationSpendsOnce(t *testing.T) {
	cfg, h, token, _, j := learningFixture(t)
	cfg.provider.key = make([]byte, 32)
	s, _ := cfg.auth.store.lookup(token, time.Now())
	cfg.provider.save(s.UserID, providerCredential{AccessToken: "personal", Expires: time.Now().Add(time.Hour)})
	entered := make(chan struct{})
	resume := make(chan struct{})
	var responses atomic.Int32
	cfg.provider.client = &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		if r.Method == "GET" {
			return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"models":[{"slug":"gpt-4o","visibility":"list"}]}`)), Header: http.Header{}}, nil
		}
		responses.Add(1)
		close(entered)
		<-resume
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader("data: {\"type\":\"response.incomplete\"}\n\n")), Header: http.Header{}}, nil
	})}
	path := "/v1/learning/episodes/" + j.ID + "/analysis"
	done := make(chan int, 1)
	go func() { done <- authCall(h, "POST", path, `{}`, token).Code }()
	<-entered
	if w := authCall(h, "POST", path, `{}`, token); w.Code != 429 {
		t.Error("concurrent admission", w.Code)
	}
	close(resume)
	if code := <-done; code != 502 {
		t.Fatal(code)
	}
	if responses.Load() != 1 {
		t.Fatal("duplicate request")
	}
}

func TestLearningAnalysisAccountAdmissionDoesNotChargeUnsent(t *testing.T) {
	cfg, h, token, _, j := learningFixture(t)
	var calls atomic.Int32
	cfg.provider.client = &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		calls.Add(1)
		return nil, fmt.Errorf("unexpected request")
	})}
	path := "/v1/learning/episodes/" + j.ID + "/analysis"
	w := authCall(h, "POST", path, `{}`, token)
	if w.Code != 503 || calls.Load() != 0 {
		t.Fatal(w.Code, calls.Load())
	}
	s, _ := cfg.auth.store.lookup(token, time.Now())
	consume, release, e := cfg.provider.reserveTranslationPlan(s.UserID, time.Now(), 100)
	if e != nil {
		t.Fatal("unsent work charged", e)
	}
	defer release()
	if e = consume(time.Now()); e != nil {
		t.Fatal(e)
	}
	w = authCall(h, "POST", path, `{}`, token)
	if w.Code != 429 {
		t.Fatal("account lock bypass", w.Code)
	}
}
