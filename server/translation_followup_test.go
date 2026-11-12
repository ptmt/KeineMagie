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

func TestTranslationFollowupConversation(t *testing.T) {
	t.Setenv("WEB_ORIGIN", "https://example.com")
	key := filepath.Join(t.TempDir(), "key")
	if err := os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PROVIDER_KEY_FILE", key)
	dir := t.TempDir()
	cfg := &serverConfig{authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json")}
	calls := 0
	cfg.httpClient = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		if strings.Contains(r.URL.Path, "models") {
			return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"models":[{"slug":"offered","visibility":"list"}]}`)), Header: http.Header{}}, nil
		}
		calls++
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatal(err)
		}
		data, _ := json.Marshal(payload["input"])
		if !strings.Contains(string(data), "лук") || !strings.Contains(string(data), "Zwiebel") || !strings.Contains(string(data), "оружие") {
			t.Errorf("missing original/context: %s", data)
		}
		if strings.Contains(payload["instructions"].(string), "оружие") {
			t.Error("question became trusted instructions")
		}
		if calls == 2 && !strings.Contains(string(data), "Bogen") {
			t.Error("previous assistant turn not supplied")
		}
		if payload["model"] != "offered" {
			t.Error("not selected personal model")
		}
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(accountTranslationSSE(`{"answer":"В контексте оружия: Bogen.","revised_text":"Bogen"}`, true, "response.completed")))}, nil
	})}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	native, s, err := cfg.auth.store.create("followup-owner", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	browser, err := cfg.auth.store.createBrowser(native, s.UserID, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if err = cfg.provider.save(s.UserID, providerCredential{AccessToken: "synthetic", Expires: time.Now().Add(time.Hour)}); err != nil {
		t.Fatal(err)
	}
	store, err := openHistory(filepath.Join(dir, "users", sessionHash(s.UserID)+".json"))
	if err != nil {
		t.Fatal(err)
	}
	original := translationRecord{ID: "original", CreatedAt: time.Now(), translationInput: translationInput{Text: "лук", SourceLanguage: "ru", TargetLanguage: "de", Instructions: "Friendly"}, translationResult: translationResult{Translation: "Zwiebel", Idioms: []idiom{}, Patterns: []pattern{}, Vocabulary: []vocabularyItem{}}}
	if err = store.append(original); err != nil {
		t.Fatal(err)
	}
	call := func(body, token, csrf string) *httptest.ResponseRecorder {
		r := httptest.NewRequest("POST", "/v1/translation-followups", strings.NewReader(body))
		r.AddCookie(&http.Cookie{Name: browserCookie, Value: token})
		r.Header.Set("Origin", "https://example.com")
		r.Header.Set("X-CSRF-Token", csrf)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	body := `{"history_id":"original","request_id":"request-1","question":"Я имел в виду оружие","locale":"ru","expected_turns":0}`
	if w := call(body, browser, ""); w.Code != 403 {
		t.Fatalf("CSRF %d %s", w.Code, w.Body.String())
	}
	w := call(body, browser, browserCSRF(browser))
	if w.Code != 201 {
		t.Fatalf("followup %d %s", w.Code, w.Body.String())
	}
	var result map[string]any
	json.Unmarshal(w.Body.Bytes(), &result)
	if result["translation"] != "Zwiebel" || result["text"] != "лук" || result["instructions"] != "Friendly" {
		t.Fatalf("original overwritten: %s", w.Body.String())
	}
	if turns, ok := result["followups"].([]any); !ok || len(turns) != 1 {
		t.Fatalf("missing durable thread %s", w.Body.String())
	}
	if w = call(body, browser, browserCSRF(browser)); w.Code != 200 || calls != 1 {
		t.Fatalf("duplicate charged %d calls=%d", w.Code, calls)
	}
	second := strings.Replace(strings.Replace(body, "request-1", "request-2", 1), `"expected_turns":0`, `"expected_turns":1`, 1)
	if w = call(second, browser, browserCSRF(browser)); w.Code != 201 || calls != 2 {
		t.Fatalf("second turn %d %s", w.Code, w.Body.String())
	}
	stale := strings.Replace(body, "request-1", "stale", 1)
	if w = call(stale, browser, browserCSRF(browser)); w.Code != 409 || calls != 2 {
		t.Fatalf("stale accepted %d", w.Code)
	}
	otherNative, other, _ := cfg.auth.store.create("other-owner", time.Now())
	otherBrowser, _ := cfg.auth.store.createBrowser(otherNative, other.UserID, time.Now())
	if w = call(body, otherBrowser, browserCSRF(otherBrowser)); w.Code != 404 || strings.Contains(w.Body.String(), "лук") {
		t.Fatalf("owner leak %d %s", w.Code, w.Body.String())
	}
	reopened, err := openHistory(store.path)
	if err != nil {
		t.Fatal(err)
	}
	items, err := reopened.list()
	if err != nil || len(items) != 1 {
		t.Fatalf("history duplicated %v", err)
	}
	encoded, _ := json.Marshal(items)
	if !strings.Contains(string(encoded), "request-2") {
		t.Fatal("thread not durable")
	}
}
