package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// Opt-in loopback only. Actual Coach/Activity handlers and stores; synthetic
// Responses transport, auth bootstrap adapter, disposable owner. Never live AI.
func TestCoachWebParityFixture(t *testing.T) {
	ready := os.Getenv("KM_COACH_WEB_FIXTURE")
	if ready == "" {
		t.Skip("explicit local browser fixture only")
	}
	dir := t.TempDir()
	key := filepath.Join(dir, "key")
	os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600)
	t.Setenv("PROVIDER_KEY_FILE", key)
	var calls atomic.Int32
	cfg := &serverConfig{authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json")}
	cfg.httpClient = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		result := `{"models":[{"slug":"gpt-6.1-terra","visibility":"list"}]}`
		if !strings.Contains(r.URL.Path, "models") {
			calls.Add(1)
			var wire map[string]any
			json.NewDecoder(r.Body).Decode(&wire)
			schema := wire["text"].(map[string]any)["format"].(map[string]any)["name"]
			if schema == "coach_assessment" {
				result = accountTranslationSSE(`{"verdict":"correct","corrected_answer":"Praktikum","explanation":"Synthetic: the answer matches the stated work-experience meaning.","uncertainty_reason":""}`, true, "response.completed")
			} else {
				result = accountTranslationSSE(`{"message":"Complete the sentence.","kind":"cloze","prompt":"Ich mache ein ___ bei euch.","target":"vocabulary.word_choice","source_id":"translation:fixture","quote":"Ich mache ein Praktikum bei euch.","answers":["Praktikum"],"incorrect_answers":[],"explanation":"A period of practical work experience.","target_text":"","answer_language":"","clue":"a period of practical work experience","clue_kind":"gloss","clue_language":"en"}`, true, "response.completed")
			}
		}
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(result))}, nil
	})}
	production, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	token, session, e := cfg.auth.store.create("web-parity-synthetic", time.Now())
	if e != nil {
		t.Fatal(e)
	}
	if e = cfg.provider.save(session.UserID, providerCredential{AccessToken: "synthetic", Expires: time.Now().Add(time.Hour)}); e != nil {
		t.Fatal(e)
	}
	history, e := openHistory(filepath.Join(dir, "users", sessionHash(session.UserID)+".json"))
	if e != nil {
		t.Fatal(e)
	}
	history.append(translationRecord{ID: "fixture", CreatedAt: time.Now(), translationInput: translationInput{SourceLanguage: "en", TargetLanguage: "de"}, translationResult: translationResult{Translation: "Ich mache ein Praktikum bei euch."}})
	done := make(chan struct{})
	static := http.HandlerFunc(publicWeb)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/__fixture/stop":
			writeJSON(w, 200, map[string]any{"calls": calls.Load()})
			select {
			case <-done:
			default:
				close(done)
			}
			return
		case "/v1/web/config":
			writeJSON(w, 200, map[string]any{"csrf_token": "fixture", "apple_available": false})
			return
		case "/v1/web/session":
			writeJSON(w, 200, map[string]any{"user": map[string]string{"id": session.UserID}, "csrf_token": "fixture", "provider": map[string]any{"connected": true, "selected_model": coachModel}})
			return
		case "/v1/provider":
			writeJSON(w, 200, map[string]any{"connected": true, "selected_model": coachModel})
			return
		case "/v1/translations", "/v1/podcasts", "/v1/podcasts/subscriptions":
			writeJSON(w, 200, map[string]any{"items": []any{}})
			return
		}
		if strings.HasPrefix(r.URL.Path, "/v1/learning/") {
			clone := r.Clone(r.Context())
			clone.Header = r.Header.Clone()
			clone.Header.Set("Authorization", "Bearer "+token)
			clone.Header.Del("Origin")
			clone.Header.Del("Cookie")
			production.ServeHTTP(w, clone)
			return
		}
		if strings.HasPrefix(r.URL.Path, "/v1/") {
			http.Error(w, "fixture blocks unrelated API", 403)
			return
		}
		static.ServeHTTP(w, r)
	}))
	defer server.Close()
	b, _ := json.Marshal(map[string]string{"url": server.URL, "owner": session.UserID})
	if e = os.WriteFile(ready, b, 0600); e != nil {
		t.Fatal(e)
	}
	select {
	case <-done:
	case <-time.After(2 * time.Minute):
		t.Fatal("fixture deadline")
	}
}
