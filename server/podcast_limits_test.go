package main

import (
	"encoding/json"
	"errors"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"
)

func TestPodcastDailyLimitExplainsEmptyLibrary(t *testing.T) {
	now := time.Date(2026, 11, 11, 10, 0, 0, 0, time.UTC)
	d := podcastData{Jobs: []podcastStoredJob{}, Budgets: map[string]podcastBudget{sessionHash("owner"): {Day: "2026-11-11", Attempts: 4}}}
	err := podcastReserve(&d, "owner", now)
	w := httptest.NewRecorder()
	podcastHTTPError(w, err)
	var body map[string]any
	if e := json.Unmarshal(w.Body.Bytes(), &body); e != nil {
		t.Fatal(e)
	}
	if w.Code != 429 || body["code"] != "podcast_daily_limit" {
		t.Fatalf("daily gate not identified: status=%d body=%s", w.Code, w.Body.String())
	}
	if body["remaining"] != float64(0) || body["limit"] != float64(4) || body["retry_after"] != float64(50400) || w.Header().Get("Retry-After") != "50400" {
		t.Fatalf("missing precise daily details: %s", w.Body.String())
	}
	if !errors.Is(err, errPodcastLimit) {
		t.Fatal("sentinel compatibility lost")
	}
}

func TestPodcastOwnerLimitsGET(t *testing.T) {
	t.Setenv("PODCAST_WORKER_URL", "")
	cfg := &serverConfig{authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json")}
	if _, e := newHandler(cfg); e != nil {
		t.Fatal(e)
	}
	token, session, _ := cfg.auth.store.create("owner", time.Now())
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	now := time.Now()
	d := podcastData{Jobs: []podcastStoredJob{}, Budgets: map[string]podcastBudget{sessionHash(session.UserID): {Day: now.UTC().Format("2006-01-02"), Attempts: 4}, sessionHash("foreign"): {Day: now.UTC().Format("2006-01-02"), Attempts: 3}}}
	if e := s.write(d); e != nil {
		t.Fatal(e)
	}
	p := &podcastService{cfg: cfg, store: s}
	r := httptest.NewRequest("GET", "/v1/podcasts", nil)
	r.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	p.handle(w, r)
	var body struct {
		Limits struct {
			DailyAttempts  int `json:"daily_attempts"`
			DailyRemaining int `json:"daily_remaining"`
			Retained       int `json:"retained"`
		} `json:"limits"`
	}
	if e := json.Unmarshal(w.Body.Bytes(), &body); e != nil {
		t.Fatal(e)
	}
	if w.Code != 200 || body.Limits.DailyAttempts != 4 || body.Limits.DailyRemaining != 0 || body.Limits.Retained != 0 {
		t.Fatalf("owner limits missing: %s", w.Body.String())
	}
}

func TestPodcastFailedAdmissionNeverCharges(t *testing.T) {
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	for i := 0; i < 6; i++ {
		_, e := s.episode("owner", "https://example.com/a.mp3", "de", "", "", "", time.Now(), false, func() error { return errors.New("backend unavailable") })
		if e == nil {
			t.Fatal("failed admission accepted")
		}
	}
	d, e := s.read()
	if e != nil || len(d.Jobs) != 0 || len(d.Budgets) != 0 {
		t.Fatal("failed admission persisted budget or job", e)
	}
}

func TestPodcastLimitReasons(t *testing.T) {
	now := time.Date(2026, 11, 11, 10, 0, 0, 0, time.UTC)
	for _, tc := range []struct {
		code, owner, state string
		count              int
	}{
		{"podcast_active_limit", "owner", "queued", 2},
		{"podcast_storage_limit", "owner", "completed", 30},
		{"podcast_global_active_limit", "foreign", "queued", 32},
		{"podcast_global_storage_limit", "foreign", "completed", 500},
	} {
		t.Run(tc.code, func(t *testing.T) {
			d := podcastData{Budgets: map[string]podcastBudget{}}
			for i := 0; i < tc.count; i++ {
				d.Jobs = append(d.Jobs, podcastStoredJob{podcastJob: podcastJob{State: tc.state}, Owner: tc.owner})
			}
			err := podcastCheckAdmission(d, "owner", now)
			var q *podcastLimitError
			if !errors.As(err, &q) || q.Code != tc.code {
				t.Fatalf("wrong gate: %v", err)
			}
			if tc.owner == "foreign" && (q.Limits.Active != 0 || q.Limits.Retained != 0) {
				t.Fatal("foreign counts exposed")
			}
		})
	}
	d := podcastData{Budgets: map[string]podcastBudget{sessionHash("owner"): {Day: "2026-11-10", Attempts: 4}}}
	if e := podcastCheckAdmission(d, "owner", now); e != nil {
		t.Fatal("previous day still charged", e)
	}
}

func TestPodcastRejectedCapacitySkipsReadiness(t *testing.T) {
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	now := time.Now()
	d := podcastData{Jobs: []podcastStoredJob{}, Budgets: map[string]podcastBudget{sessionHash("owner"): {Day: now.UTC().Format("2006-01-02"), Attempts: 4}}}
	if e := s.write(d); e != nil {
		t.Fatal(e)
	}
	calls := 0
	_, e := s.episode("owner", "https://example.com/new.mp3", "de", "", "", "", now, false, func() error { calls++; return nil })
	if !errors.Is(e, errPodcastLimit) || calls != 0 {
		t.Fatalf("capacity checked after upstream readiness: calls=%d error=%v", calls, e)
	}
	after, _ := s.read()
	if after.Budgets[sessionHash("owner")].Attempts != 4 || len(after.Jobs) != 0 {
		t.Fatal("rejected admission changed store")
	}
}
