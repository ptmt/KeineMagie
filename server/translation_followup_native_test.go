package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestNativeFollowupExpectedOwnerBeforeWork(t *testing.T) {
	t.Setenv("WEB_ORIGIN", "https://example.com")
	dir := t.TempDir()
	key := filepath.Join(dir, "key")
	if err := os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PROVIDER_KEY_FILE", key)
	cfg := &serverConfig{authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json")}
	handler, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	token, _, err := cfg.auth.store.create("native-owner", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest("POST", "/v1/translation-followups", strings.NewReader(`{"history_id":"saved","request_id":"one","question":"why","locale":"en","expected_turns":0}`))
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("X-Translation-Owner", "different-owner")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != 403 {
		t.Fatalf("expected owner fence, got %d", response.Code)
	}
}

func TestNativeFollowupOptionalOwnerWebCompatibilityAndCSRF(t *testing.T) {
	calls := 0
	cfg, h, browser, owner, store := followupFixture(t, transportFunc(func(*http.Request) (*http.Response, error) { calls++; return nil, io.ErrUnexpectedEOF }))
	_, err := store.followupRecord("saved", func(r *translationRecord) error {
		r.Followups = append(r.Followups, translationFollowup{RequestID: "r1", Question: "оружие", Answer: "saved answer"})
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, expected, origin, csrf string
		want                         int
	}{
		{"legacy web without owner", "", "https://example.com", browserCSRF(browser), 200},
		{"matching owner", owner, "https://example.com", browserCSRF(browser), 200},
		{"wrong owner", "other", "https://example.com", browserCSRF(browser), 403},
		{"missing csrf", "", "https://example.com", "", 403},
		{"wrong csrf", "", "https://example.com", "wrong", 403},
		{"cross origin", "", "https://other.example", browserCSRF(browser), 403},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := httptest.NewRequest("POST", "/v1/translation-followups", strings.NewReader(followupValidBody))
			r.AddCookie(&http.Cookie{Name: browserCookie, Value: browser})
			r.Header.Set("Origin", tc.origin)
			r.Header.Set("X-CSRF-Token", tc.csrf)
			if tc.expected != "" {
				r.Header.Set("X-Translation-Owner", tc.expected)
			}
			w := httptest.NewRecorder()
			h.ServeHTTP(w, r)
			if w.Code != tc.want {
				t.Fatalf("got %d, want %d", w.Code, tc.want)
			}
		})
	}
	token, otherSession, err := cfg.auth.store.create("other-owner", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	// create takes an Apple subject, not the generated authenticated UserID.
	// A mismatched expected-owner header is rejected before history lookup;
	// an absent or matching header reaches the owner-scoped missing record.
	for _, tc := range []struct {
		expected string
		want     int
	}{{"", 404}, {otherSession.UserID, 404}, {"other-owner", 403}} {
		r := httptest.NewRequest("POST", "/v1/translation-followups", strings.NewReader(followupValidBody))
		r.Header.Set("Authorization", "Bearer "+token)
		r.Header.Set("X-Translation-Owner", tc.expected)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != tc.want {
			t.Fatalf("cross-owner header %q: got %d, want %d", tc.expected, w.Code, tc.want)
		}
	}
	if calls != 0 || followupQuotaAttempts(t, cfg, owner) != 0 {
		t.Fatal("replay/rejection invoked or billed upstream")
	}
}

// Serialize the actual production Go record, not an invented Swift fixture.
func TestNativeFollowupWireFixture(t *testing.T) {
	output := os.Getenv("KM_NATIVE_FOLLOWUP_WIRE")
	if output == "" {
		t.Skip("wire output not requested")
	}
	revised := "Vorschlag"
	source := "предложение"
	current := "текущий текст"
	translated := "Aktueller Text"
	record := translationRecord{ID: "wire-record", CreatedAt: time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC), translationInput: translationInput{Text: "оригинал", SourceLanguage: "ru", TargetLanguage: "de"}, translationResult: translationResult{Translation: "Original", Idioms: []idiom{}, Patterns: []pattern{}, Vocabulary: []vocabularyItem{}}}
	records := []translationRecord{record}
	record.Followups = []translationFollowup{
		{RequestID: "nullable", Question: "why?", Answer: "Explanation", CreatedAt: record.CreatedAt},
		{RequestID: "legacy", Question: "wording?", Answer: "Legacy", RevisedText: &revised, CurrentSource: &current, CurrentTranslation: &translated, CreatedAt: record.CreatedAt},
		{RequestID: "paired", Question: "context?", Answer: "Pair", RevisedText: &revised, RevisedSourceText: &source, CurrentSource: &current, CurrentTranslation: &translated, CreatedAt: record.CreatedAt},
	}
	records = append(records, record)
	data, err := json.Marshal(records)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(output, data, 0600); err != nil {
		t.Fatal(err)
	}
}
