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

// Synthetic Responses wire fixture, not a claim of live model quality.
func TestCoachAssessmentContextAndIdempotency(t *testing.T) {
	key := filepath.Join(t.TempDir(), "key")
	if e := os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600); e != nil {
		t.Fatal(e)
	}
	t.Setenv("PROVIDER_KEY_FILE", key)
	dir := t.TempDir()
	calls := 0
	cfg := &serverConfig{authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json")}
	cfg.httpClient = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		text := `{"models":[{"slug":"gpt-6.1-terra","visibility":"list"}]}`
		if !strings.Contains(r.URL.Path, "models") {
			calls++
			var p map[string]any
			if e := json.NewDecoder(r.Body).Decode(&p); e != nil {
				t.Fatal(e)
			}
			if p["model"] != coachModel || p["store"] != false || p["stream"] != true || r.URL.String() != "https://api.openai.com/v1/responses" {
				t.Fatal("wire", p)
			}
			content := p["input"].([]any)[0].(map[string]any)["content"].(string)
			for _, want := range []string{"Ich war einmal ___ diesem Kurs dabei.", "Ich war einmal bei diesem Kurs dabei.", "  beim  ", "verb_government.preposition_case", "learner_answer", "assisted"} {
				if !strings.Contains(content, want) {
					t.Errorf("missing context %q: %s", want, content)
				}
			}
			text = accountTranslationSSE(`{"verdict":"incorrect","corrected_answer":"bei","explanation":"Beim means bei dem. Here diesem already supplies the determiner, so use bei.","uncertainty_reason":""}`, true, "response.completed")
		}
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(text))}, nil
	})}
	h, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	token, s, e := cfg.auth.store.create("assessment-owner", time.Now())
	if e != nil {
		t.Fatal(e)
	}
	if e = cfg.provider.save(s.UserID, providerCredential{AccessToken: "synthetic", Expires: time.Now().Add(time.Hour)}); e != nil {
		t.Fatal(e)
	}
	history, e := openHistory(filepath.Join(dir, "users", sessionHash(s.UserID)+".json"))
	if e != nil {
		t.Fatal(e)
	}
	if e = history.append(translationRecord{ID: "course", translationInput: translationInput{TargetLanguage: "de"}, translationResult: translationResult{Translation: "Ich war einmal bei diesem Kurs dabei."}}); e != nil {
		t.Fatal(e)
	}
	if e = cfg.coachStore(s.UserID).transaction(true, func(d *coachData) error {
		d.Turns = append(d.Turns, coachTurn{ID: "exercise", State: "completed", Language: "de", Result: &coachResult{Kind: "preposition_case", Prompt: "Ich war einmal ___ diesem Kurs dabei.", Target: "verb_government.preposition_case", SourceID: "translation:course", Quote: "Ich war einmal bei diesem Kurs dabei.", Answers: []string{"beim"}}})
		return nil
	}); e != nil {
		t.Fatal(e)
	}
	call := func(method, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, "/v1/learning/coach", strings.NewReader(body))
		r.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	body := `{"request_id":"check","action":"answer","turn_id":"exercise","text":"  beim  ","locale":"en"}`
	w := call("POST", body)
	if calls != 1 || w.Code != 200 || !strings.Contains(w.Body.String(), `"verdict":"incorrect"`) || !strings.Contains(w.Body.String(), `"answer":"  beim  "`) {
		t.Fatalf("actual contextual assessment missing: calls=%d %d %s", calls, w.Code, w.Body.String())
	}
	if w = call("POST", body); w.Code != 200 || calls != 1 {
		t.Fatal("duplicate", w.Code, calls)
	}
	if w = call("GET", ""); w.Code != 200 || calls != 1 || !strings.Contains(w.Body.String(), `"needs_practice":1`) {
		t.Fatal("read/evidence", w.Body.String(), calls)
	}
}
