package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestActivityDatesAndFailures(t *testing.T) {
	for _, zone := range []string{"Europe/Berlin", "America/New_York", "Asia/Kathmandu", "Pacific/Kiritimati"} {
		t.Run(zone, func(t *testing.T) {
			cfg := &serverConfig{historyPath: filepath.Join(t.TempDir(), "history.json")}
			loc, e := time.LoadLocation(zone)
			if e != nil {
				t.Fatal(e)
			}
			start := time.Date(2026, 10, 19, 0, 0, 0, 0, loc)
			last := start.AddDate(0, 0, 6).Add(23 * time.Hour)
			original := coachAttempt{ID: "original", Answer: "a", Outcome: "wrong", At: last, AssessmentState: "completed", Excluded: true}
			if e = cfg.coachStore("owner").transaction(true, func(d *coachData) error {
				reset := last.Add(time.Hour)
				d.ResetAt = &reset
				d.Turns = []coachTurn{{ID: "one", Result: &coachResult{Kind: "cloze"}, PriorAttempts: []coachAttempt{original}, Attempt: &coachAttempt{ID: "recheck", Answer: "a", Outcome: "ambiguous", At: last, AssessmentState: "failed"}}, {ID: "discussion", Result: &coachResult{Kind: "clarification"}, Attempt: &original}}
				return nil
			}); e != nil {
				t.Fatal(e)
			}
			got := cfg.activityWeek("owner", start, loc)
			if got.Days[6].KnownCount != 1 {
				t.Fatalf("prior successful explicit Check counted wrong: %+v", got)
			}
			path := cfg.coachStore("owner").lock.path
			before, _ := os.ReadFile(path)
			reopened := &serverConfig{historyPath: cfg.historyPath}
			reopened.activityWeek("owner", start, loc)
			after, _ := os.ReadFile(path)
			if string(before) != string(after) {
				t.Fatal("GET mutated history")
			}
			if e = os.WriteFile(path, []byte("broken"), 0600); e != nil {
				t.Fatal(e)
			}
			failed := cfg.activityWeek("owner", start, loc)
			if failed.Sources["coach"] != "unavailable" || failed.Days[6].Coverage != "partial" {
				t.Fatal("failure became zero")
			}
		})
	}
}

func TestActivityHTTPReadOnlyContract(t *testing.T) {
	dir := t.TempDir()
	key := filepath.Join(dir, "key")
	if err := os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PROVIDER_KEY_FILE", key)
	cfg := &serverConfig{historyPath: filepath.Join(dir, "history.json"), authPath: filepath.Join(dir, "auth.json"), httpClient: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) { t.Fatal("activity invoked provider"); return nil, nil })}}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	token, session, err := cfg.auth.store.create("synthetic-activity", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	// Export a genuine handler response with saved successful translation evidence.
	store, err := openHistory(filepath.Join(dir, "users", sessionHash(session.UserID)+".json"))
	if err != nil {
		t.Fatal(err)
	}
	if err = store.append(translationRecord{ID: "wire-success", CreatedAt: time.Date(2026, 10, 19, 12, 0, 0, 0, time.UTC), translationResult: translationResult{Translation: "saved success"}}); err != nil {
		t.Fatal(err)
	}
	for _, tt := range []struct {
		method, path, owner, token string
		status                     int
	}{
		{"GET", "/v1/learning/activity?start=2026-10-19&time_zone=Europe%2FBerlin", session.UserID, token, 200},
		{"POST", "/v1/learning/activity?start=2026-10-19&time_zone=UTC", session.UserID, token, 405},
		{"GET", "/v1/learning/activity?start=bad&time_zone=UTC", session.UserID, token, 400},
		{"GET", "/v1/learning/activity?start=2026-10-19&time_zone=bad", session.UserID, token, 400},
		{"GET", "/v1/learning/activity?start=2026-10-19&time_zone=UTC", "foreign", token, 403},
		{"GET", "/v1/learning/activity?start=2026-10-19&time_zone=UTC", session.UserID, "invalid", 401},
	} {
		r := httptest.NewRequest(tt.method, tt.path, nil)
		r.Header.Set("Authorization", "Bearer "+tt.token)
		r.Header.Set("X-Activity-Owner", tt.owner)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != tt.status {
			t.Fatalf("%s: got %d want %d: %s", tt.path, w.Code, tt.status, w.Body.String())
		}
		if w.Code == 200 {
			if path := os.Getenv("ACTIVITY_WIRE_PATH"); path != "" {
				if err := os.WriteFile(path, w.Body.Bytes(), 0600); err != nil {
					t.Fatal(err)
				}
			}
			var got activitySnapshot
			if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil || len(got.Days) != 7 || w.Header().Get("Cache-Control") != "no-store" {
				t.Fatal("wire contract", err)
			}
		}
	}
}

// Synthetic retained records; never a production account or provider.
func TestActivityRetainedCompletionsLocalDays(t *testing.T) {
	cfg := &serverConfig{historyPath: filepath.Join(t.TempDir(), "history.json")}
	at := time.Date(2026, 3, 28, 23, 30, 0, 0, time.UTC)
	err := cfg.coachStore("alice").transaction(true, func(d *coachData) error {
		d.Turns = []coachTurn{
			{ID: "answered", Result: &coachResult{Kind: "cloze"}, Attempt: &coachAttempt{ID: "a", Answer: "wrong", Outcome: "wrong", At: at, AssessmentState: "completed"}},
			{ID: "skip", Attempt: &coachAttempt{Outcome: "skipped", At: at}},
			{ID: "pending", Attempt: &coachAttempt{Answer: "answer", At: at, AssessmentState: "pending"}},
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	err = cfg.dictationTransaction("alice", true, func(d *dictationData) error {
		d.Items = []dictationRecord{{ID: "checked", Checked: true, Assessment: &dictationAssessmentReceipt{At: at.Format(time.RFC3339), State: "not_requested"}}, {ID: "legacy", Checked: true, Created: "2026-03-28T00:00:00Z"}}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	loc, _ := time.LoadLocation("Europe/Berlin")
	start := time.Date(2026, 3, 23, 0, 0, 0, 0, loc)
	got := cfg.activityWeek("alice", start, loc)
	if len(got.Days) != 7 || got.Days[6].KnownCount != 2 || got.Days[5].KnownCount != 0 {
		t.Fatalf("local days: %+v", got)
	}
	if got.Days[6].Coverage != "partial" || got.Days[5].Coverage != "partial" {
		t.Fatal("unknown history became verified zero")
	}
	if got.Sources["translator"] != "retained" || got.Sources["podcasts"] != "retained" {
		t.Fatal("inferred exercise completions")
	}
	other := cfg.activityWeek("bob", start, loc)
	for _, day := range other.Days {
		if day.KnownCount != 0 {
			t.Fatal("cross-owner leak")
		}
	}
}

func TestActivitySuccessfulTranslationsRetainedBeyondListLimit(t *testing.T) {
	cfg := &serverConfig{historyPath: filepath.Join(t.TempDir(), "history.json")}
	store, err := openHistory(filepath.Join(filepath.Dir(cfg.historyPath), "users", sessionHash("alice")+".json"))
	if err != nil {
		t.Fatal(err)
	}
	at := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	records := []translationRecord{}
	for i := 0; i < 105; i++ {
		records = append(records, translationRecord{ID: fmt.Sprintf("saved-%d", i), CreatedAt: at, translationResult: translationResult{Translation: "successful"}})
	}
	records = append(records, records[0], translationRecord{ID: "pending", CreatedAt: at}, translationRecord{ID: "undated", translationResult: translationResult{Translation: "saved"}})
	if err = store.locked(func() error { return store.write(records) }); err != nil {
		t.Fatal(err)
	}
	got := cfg.activityWeek("alice", at.Truncate(24*time.Hour), time.UTC)
	if got.Sources["translator"] != "retained" || got.Days[0].KnownCount != 105 || got.Undated != 1 {
		t.Fatalf("successful translations: %+v", got)
	}
	for _, day := range cfg.activityWeek("bob", at.Truncate(24*time.Hour), time.UTC).Days {
		if day.KnownCount != 0 {
			t.Fatal("owner leak")
		}
	}
	if err = store.delete("saved-1"); err != nil {
		t.Fatal(err)
	}
	reopened := &serverConfig{historyPath: cfg.historyPath}
	if got = reopened.activityWeek("alice", at.Truncate(24*time.Hour), time.UTC); got.Days[0].KnownCount != 104 || got.Days[0].Coverage != "partial" {
		t.Fatalf("deleted completion retained: %+v", got)
	}
	if err = os.WriteFile(store.path, []byte("broken"), 0600); err != nil {
		t.Fatal(err)
	}
	if got = reopened.activityWeek("alice", at.Truncate(24*time.Hour), time.UTC); got.Sources["translator"] != "unavailable" || got.Days[0].Coverage != "partial" {
		t.Fatal("failure became verified zero")
	}
}

func TestActivityDaySourceBreakdown(t *testing.T) {
	cfg := &serverConfig{historyPath: filepath.Join(t.TempDir(), "history.json")}
	at := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	if err := cfg.coachStore("owner").transaction(true, func(d *coachData) error {
		d.Turns = []coachTurn{{ID: "checked", Result: &coachResult{Kind: "cloze"}, Attempt: &coachAttempt{ID: "receipt", Answer: "a", Outcome: "wrong", At: at, AssessmentState: "completed"}}}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	data, err := json.Marshal(cfg.activityWeek("owner", at.Truncate(24*time.Hour), time.UTC))
	if err != nil {
		t.Fatal(err)
	}
	var wire struct {
		Days []struct {
			Counts map[string]int `json:"counts"`
		} `json:"days"`
	}
	if err = json.Unmarshal(data, &wire); err != nil {
		t.Fatal(err)
	}
	if wire.Days[0].Counts["coach"] != 1 {
		t.Fatalf("missing accurate day breakdown: %s", data)
	}
	for _, source := range []string{"coach", "dictation", "translator", "podcasts"} {
		if _, ok := wire.Days[0].Counts[source]; !ok {
			t.Fatalf("missing %s: %s", source, data)
		}
	}
}
