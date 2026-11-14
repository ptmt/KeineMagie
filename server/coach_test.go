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

// All provider data is synthetic and confined to this test transport.
func TestCoachOwnerChat(t *testing.T) {
	t.Setenv("WEB_ORIGIN", "https://example.com")
	key := filepath.Join(t.TempDir(), "key")
	if err := os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PROVIDER_KEY_FILE", key)
	dir := t.TempDir()
	calls := 0
	offered := false
	cfg := &serverConfig{authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json")}
	cfg.httpClient = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		text := `{"models":[{"slug":"luna","visibility":"list"}]}`
		if strings.Contains(r.URL.Path, "models") {
			if offered {
				text = `{"models":[{"slug":"gpt-6.1-terra","visibility":"list"}]}`
			}
		} else {
			calls++
			var payload map[string]any
			json.NewDecoder(r.Body).Decode(&payload)
			if payload["model"] != "gpt-6.1-terra" {
				t.Error("wrong model")
			}
			if payload["store"] != false || payload["stream"] != true || payload["max_output_tokens"] != float64(2400) || r.URL.String() != "https://api.openai.com/v1/responses" {
				t.Error("Responses wire contract violated")
			}
			format := payload["text"].(map[string]any)["format"].(map[string]any)
			schema := format["schema"].(map[string]any)
			if format["type"] != "json_schema" || format["strict"] != true || schema["additionalProperties"] != false || len(schema["required"].([]any)) != len(schema["properties"].(map[string]any)) {
				t.Error("strict schema contract violated")
			}
			if payload["tools"] != nil {
				t.Error("unexpected tools")
			}
			text = accountTranslationSSE(`{"message":"Ergänze den Satz.","kind":"cloze","prompt":"Ich warte ___ den Bus.","target":"verb_government.preposition_case","source_id":"translation:original","quote":"Ich warte auf den Bus.","answers":["auf"],"incorrect_answers":["für"],"explanation":"warten auf + Akkusativ"}`, true, "response.completed")
		}
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(text))}, nil
	})}
	h, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	token, s, e := cfg.auth.store.create("coach-owner", time.Now())
	if e != nil {
		t.Fatal(e)
	}
	browser, e := cfg.auth.store.createBrowser(token, s.UserID, time.Now())
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
	if e = history.append(translationRecord{ID: "original", CreatedAt: time.Now(), translationInput: translationInput{Text: "Я жду автобус.", SourceLanguage: "ru", TargetLanguage: "de"}, translationResult: translationResult{Translation: "Ich warte auf den Bus."}}); e != nil {
		t.Fatal(e)
	}
	call := func(method, body, auth string, csrf bool) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, "/v1/learning/coach", strings.NewReader(body))
		r.AddCookie(&http.Cookie{Name: browserCookie, Value: auth})
		r.Header.Set("Origin", "https://example.com")
		if csrf {
			r.Header.Set("X-CSRF-Token", browserCSRF(auth))
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	if w := call("GET", "", browser, false); w.Code != 200 || calls != 0 {
		t.Fatalf("GET must load without inference: %d %s", w.Code, w.Body.String())
	}
	body := `{"request_id":"turn-1","action":"message","text":"Practice","locale":"en"}`
	if w := call("POST", body, browser, false); w.Code != 403 {
		t.Fatalf("CSRF %d", w.Code)
	}
	if w := call("POST", body, browser, true); w.Code != 503 || calls != 0 {
		t.Fatalf("exact owner catalog gate: %d calls=%d %s", w.Code, calls, w.Body.String())
	}
	if w := call("POST", body, browser, true); !strings.Contains(w.Body.String(), `"code":"coach_model_unavailable"`) {
		t.Fatal("missing typed localized error", w.Body.String())
	}
	offered = true
	w := call("POST", body, browser, true)
	if w.Code != 200 {
		t.Fatalf("chat: %d %s", w.Code, w.Body.String())
	}
	if strings.Contains(w.Body.String(), `"answers"`) || strings.Contains(w.Body.String(), "warten auf +") || strings.Contains(w.Body.String(), `"quote"`) {
		t.Fatal("answer leaked before attempt")
	}
	if w = call("POST", body, browser, true); w.Code != 200 || calls != 1 {
		t.Fatalf("duplicate inference %d calls=%d", w.Code, calls)
	}
	answer := `{"request_id":"answer-1","action":"answer","turn_id":"turn-1","text":"auf","locale":"en"}`
	w = call("POST", answer, browser, true)
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"outcome":"correct"`) {
		t.Fatalf("answer %d %s", w.Code, w.Body.String())
	}
	if w = call("POST", answer, browser, true); w.Code != 200 || calls != 1 {
		t.Fatal("answer retry inferred")
	}
	// Reproduce the screenshot without regrading an unrecognized attempt or changing it.
	for _, sample := range []struct{ answer, outcome string }{{"bei", "correct"}, {"beim", "ambiguous"}} {
		id := "course-" + sample.answer
		if err := cfg.coachStore(s.UserID).transaction(true, func(d *coachData) error {
			d.Turns = append(d.Turns, coachTurn{ID: id, State: "completed", Language: "de", Result: &coachResult{Kind: "preposition_case", Prompt: "Ich war einmal ___ diesem Kurs dabei.", Answers: []string{"bei"}, SourceID: "translation:original", Quote: "Ich war einmal bei diesem Kurs dabei.", Explanation: "Bei takes the dative. Beim means bei dem; diesem is already present."}})
			return nil
		}); err != nil {
			t.Fatal(err)
		}
		payload, _ := json.Marshal(coachInput{RequestID: "answer-" + id, Action: "answer", TurnID: id, Text: sample.answer, Locale: "en"})
		w = call("POST", string(payload), browser, true)
		if w.Code != 200 {
			t.Fatal(w.Code)
		}
		if err := cfg.coachStore(s.UserID).transaction(false, func(d *coachData) error {
			a := coachFind(d, id).Attempt
			if a.Answer != sample.answer || a.Outcome != sample.outcome {
				t.Fatalf("attempt changed: %#v", a)
			}
			return nil
		}); err != nil {
			t.Fatal(err)
		}
	}
	other, otherSession, _ := cfg.auth.store.create("another-owner", time.Now())
	otherBrowser, _ := cfg.auth.store.createBrowser(other, otherSession.UserID, time.Now())
	if w = call("GET", "", otherBrowser, false); w.Code != 200 || strings.Contains(w.Body.String(), "Ich warte") {
		t.Fatal("owner leak")
	}
	w = call("GET", "", browser, false)
	if !strings.Contains(w.Body.String(), `"distinct_examples":1`) {
		t.Fatalf("missing evidence %s", w.Body.String())
	}
	// Reopen through a new handler: no automatic request/retry and durable answer.
	h, e = newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	w = call("GET", "", browser, false)
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"outcome":"correct"`) || calls != 1 {
		t.Fatalf("not durable %s", w.Body.String())
	}
}
