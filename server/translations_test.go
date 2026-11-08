package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

const translationFixture = `{"translation":"Привет","idioms":[{"expression":"Hallo sagen","meaning":"поздороваться","example":"Ich sage Hallo."}],"patterns":[{"pattern":"Ich sage …","explanation":"Я говорю …"}],"vocabulary":[{"word":"Hallo","meaning":"привет"}]}`

func translationRequest(h http.Handler, method, body, token string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, "/v1/translations", strings.NewReader(body))
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func TestTranslationsFailClosedWithoutProviderKey(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("missing provider key reached upstream")
		w.WriteHeader(http.StatusBadGateway)
	}))
	defer upstream.Close()
	path := filepath.Join(t.TempDir(), "history.json")
	h, err := newHandler(&serverConfig{authToken: "test-token", baseURL: upstream.URL, httpClient: upstream.Client(), historyPath: path})
	if err != nil {
		t.Fatal(err)
	}
	for _, body := range []string{`{"text":"Hallo","source_language":"de","target_language":"ru"}`, `{}`} {
		w := translationRequest(h, http.MethodPost, body, "test-token")
		if w.Code != http.StatusServiceUnavailable {
			t.Errorf("got %d, want 503: %s", w.Code, w.Body.String())
		}
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("missing provider key persisted history: %v", err)
	}
}

func TestTranslationsRequireConfiguredAuthorization(t *testing.T) {
	for _, method := range []string{http.MethodPost, http.MethodGet} {
		for _, tc := range []struct {
			name, configured, supplied string
			status                     int
		}{
			{"unconfigured", "", "", 503}, {"unconfigured supplied", "", "anything", 503}, {"missing", "test-token", "", 401}, {"wrong", "test-token", "wrong", 401},
		} {
			t.Run(method+tc.name, func(t *testing.T) {
				h, err := newHandler(&serverConfig{authToken: tc.configured, historyPath: filepath.Join(t.TempDir(), "history.json")})
				if err != nil {
					t.Fatal(err)
				}
				w := translationRequest(h, method, `{}`, tc.supplied)
				if w.Code != tc.status {
					t.Fatalf("got %d want %d: %s", w.Code, tc.status, w.Body.String())
				}
			})
		}
	}
}

func TestTranslationsRejectInvalidInput(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("invalid request reached upstream")
		w.WriteHeader(500)
	}))
	defer upstream.Close()
	h, err := newHandler(&serverConfig{authToken: "test-token", apiKey: "test-upstream-key", baseURL: upstream.URL, httpClient: upstream.Client(), historyPath: filepath.Join(t.TempDir(), "history.json")})
	if err != nil {
		t.Fatal(err)
	}
	for _, body := range []string{`{`, `{}`, `{"text":"  ","source_language":"de","target_language":"ru"}`, `{"text":"a","source_language":"en","target_language":"ru"}`, `{"text":"a","source_language":"de","target_language":"de"}`, `{"text":"a","source_language":"ru","target_language":"xx"}`, `{"text":"a","source_language":"de","target_language":"ru","extra":true}`, `{"text":"a","source_language":"de","target_language":"ru"} {}`, `{"text":"` + strings.Repeat("я", 8001) + `","source_language":"ru","target_language":"de"}`, strings.Repeat(" ", 65537)} {
		w := translationRequest(h, http.MethodPost, body, "test-token")
		if w.Code != 400 {
			t.Errorf("got %d want 400, body length %d", w.Code, len(body))
		}
	}
	w := translationRequest(h, http.MethodDelete, "", "test-token")
	if w.Code != 405 {
		t.Errorf("method got %d", w.Code)
	}
	w = translationRequest(h, http.MethodOptions, "", "")
	if w.Code != 204 {
		t.Errorf("options got %d", w.Code)
	}
}

func TestHistoryPersistsPrivateNewestFirstConcurrentAndBounded(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"message": map[string]any{"content": translationFixture}}}})
	}))
	defer upstream.Close()
	path := filepath.Join(t.TempDir(), "private", "history.json")
	cfg := &serverConfig{authToken: "test-token", apiKey: "test-key", textModel: "test-model", baseURL: upstream.URL, httpClient: upstream.Client(), historyPath: path}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	var empty struct {
		Items []translationRecord `json:"items"`
	}
	w := translationRequest(h, "GET", "", "test-token")
	if w.Code != 200 {
		t.Fatalf("empty GET %d: %s", w.Code, w.Body.String())
	}
	if err := json.Unmarshal(w.Body.Bytes(), &empty); err != nil || empty.Items == nil || len(empty.Items) != 0 {
		t.Fatalf("empty history %s", w.Body.String())
	}
	var wg sync.WaitGroup
	for i := 0; i < 105; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			w := translationRequest(h, "POST", fmt.Sprintf(`{"text":"Привет %d","source_language":"ru","target_language":"de"}`, i), "test-token")
			if w.Code != 201 {
				t.Errorf("POST %d: %s", w.Code, w.Body.String())
			}
		}(i)
	}
	wg.Wait()
	h, err = newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	w = translationRequest(h, "GET", "", "test-token")
	var got struct {
		Items []translationRecord `json:"items"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if w.Code != 200 || len(got.Items) != 100 {
		t.Fatalf("history %d items %d", w.Code, len(got.Items))
	}
	ids := map[string]bool{}
	for i, item := range got.Items {
		if ids[item.ID] {
			t.Error("duplicate ID")
		}
		ids[item.ID] = true
		if i > 0 && got.Items[i-1].CreatedAt.Before(item.CreatedAt) {
			t.Error("not newest first")
		}
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0600 {
		t.Errorf("file mode %o", info.Mode().Perm())
	}
	info, err = os.Stat(filepath.Dir(path))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0700 {
		t.Errorf("dir mode %o", info.Mode().Perm())
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var all []translationRecord
	if err = json.Unmarshal(data, &all); err != nil || len(all) != 105 {
		t.Fatalf("durable history length %d err %v", len(all), err)
	}
	files, err := filepath.Glob(filepath.Join(filepath.Dir(path), ".history-*"))
	if err != nil || len(files) != 0 {
		t.Fatalf("temporary files: %v %v", files, err)
	}
}

func TestTranslationRejectsUpstreamFailuresWithoutSaving(t *testing.T) {
	for _, tc := range []struct {
		name   string
		status int
		body   string
	}{
		{"rate limit", 429, `{"secret":"do not leak"}`}, {"server", 500, "secret upstream detail"}, {"malformed envelope", 200, `{`}, {"empty choices", 200, `{"choices":[]}`},
		{"invalid JSON result", 200, `{"choices":[{"message":{"content":"not JSON"}}]}`},
		{"missing fields", 200, `{"choices":[{"message":{"content":"{}"}}]}`},
		{"blank translation", 200, `{"choices":[{"message":{"content":"{\"translation\":\" \",\"idioms\":[],\"patterns\":[],\"vocabulary\":[]}"}}]}`},
		{"null arrays", 200, `{"choices":[{"message":{"content":"{\"translation\":\"x\",\"idioms\":null,\"patterns\":[],\"vocabulary\":[]}"}}]}`},
		{"bad idiom", 200, `{"choices":[{"message":{"content":"{\"translation\":\"x\",\"idioms\":[{}],\"patterns\":[],\"vocabulary\":[]}"}}]}`},
		{"bad pattern", 200, `{"choices":[{"message":{"content":"{\"translation\":\"x\",\"idioms\":[],\"patterns\":[{}],\"vocabulary\":[]}"}}]}`},
		{"bad vocabulary", 200, `{"choices":[{"message":{"content":"{\"translation\":\"x\",\"idioms\":[],\"patterns\":[],\"vocabulary\":[{}]}"}}]}`},
		{"oversized envelope", 200, strings.Repeat(" ", 1048577)},
	} {
		t.Run(tc.name, func(t *testing.T) {
			upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(tc.status)
				_, _ = w.Write([]byte(tc.body))
			}))
			defer upstream.Close()
			h, err := newHandler(&serverConfig{authToken: "test-token", apiKey: "test-upstream-key", baseURL: upstream.URL, httpClient: upstream.Client(), historyPath: filepath.Join(t.TempDir(), "history.json")})
			if err != nil {
				t.Fatal(err)
			}
			w := translationRequest(h, "POST", `{"text":"Hallo","source_language":"de","target_language":"ru"}`, "test-token")
			if w.Code != 502 || strings.Contains(w.Body.String(), "secret") {
				t.Errorf("got %d: %s", w.Code, w.Body.String())
			}
			w = translationRequest(h, "GET", "", "test-token")
			if strings.TrimSpace(w.Body.String()) != `{"items":[]}` {
				t.Errorf("saved failure: %s", w.Body.String())
			}
		})
	}
}

func TestTranslationCancellationDoesNotPersist(t *testing.T) {
	started := make(chan struct{})
	cancelled := make(chan struct{})
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Consume the request before waiting so net/http can observe disconnect.
		var payload any
		_ = json.NewDecoder(r.Body).Decode(&payload)
		close(started)
		select {
		case <-r.Context().Done():
			close(cancelled)
		case <-time.After(3 * time.Second):
		}
	}))
	defer upstream.Close()
	h, err := newHandler(&serverConfig{authToken: "test-token", apiKey: "test-upstream-key", baseURL: upstream.URL, httpClient: upstream.Client(), historyPath: filepath.Join(t.TempDir(), "history.json")})
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	r := httptest.NewRequest("POST", "/v1/translations", strings.NewReader(`{"text":"Hallo","source_language":"de","target_language":"ru"}`)).WithContext(ctx)
	r.Header.Set("Authorization", "Bearer test-token")
	done := make(chan struct{})
	w := httptest.NewRecorder()
	go func() { h.ServeHTTP(w, r); close(done) }()
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("upstream not started")
	}
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("handler did not cancel")
	}
	select {
	case <-cancelled:
	case <-time.After(time.Second):
		t.Fatal("upstream context not cancelled")
	}
	if w.Code != 502 {
		t.Fatalf("cancel response %d", w.Code)
	}
	w = translationRequest(h, "GET", "", "test-token")
	if strings.TrimSpace(w.Body.String()) != `{"items":[]}` {
		t.Fatalf("saved cancelled request: %s", w.Body.String())
	}
}

func TestHistoryRejectsCorruptionAndWriteFailure(t *testing.T) {
	path := filepath.Join(t.TempDir(), "history.json")
	if err := os.WriteFile(path, []byte("broken"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := newHandler(&serverConfig{historyPath: path}); err == nil {
		t.Fatal("corrupt history accepted")
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := os.Mkdir(path, 0700); err != nil {
			t.Error(err)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"message": map[string]any{"content": translationFixture}}}})
	}))
	defer upstream.Close()
	h, err := newHandler(&serverConfig{authToken: "test-token", apiKey: "test-upstream-key", baseURL: upstream.URL, httpClient: upstream.Client(), historyPath: path})
	if err != nil {
		t.Fatal(err)
	}
	w := translationRequest(h, "POST", `{"text":"Hallo","source_language":"de","target_language":"ru"}`, "test-token")
	if w.Code != 500 {
		t.Fatalf("failed persistence returned %d: %s", w.Code, w.Body.String())
	}
	w = translationRequest(h, "GET", "", "test-token")
	if w.Code != 500 {
		t.Fatalf("failed read returned %d", w.Code)
	}
}

func TestCancelledBeforePersistenceDoesNotSave(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	client := &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		cancel()
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"choices":[{"message":{"content":"{\"translation\":\"Привет\",\"idioms\":[],\"patterns\":[],\"vocabulary\":[]}"}}]}`)), Header: make(http.Header)}, nil
	})}
	path := filepath.Join(t.TempDir(), "history.json")
	h, err := newHandler(&serverConfig{authToken: "test-token", apiKey: "test-upstream-key", baseURL: "http://test.invalid", httpClient: client, historyPath: path})
	if err != nil {
		t.Fatal(err)
	}
	r := httptest.NewRequest("POST", "/v1/translations", strings.NewReader(`{"text":"Hallo","source_language":"de","target_language":"ru"}`)).WithContext(ctx)
	r.Header.Set("Authorization", "Bearer test-token")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 502 {
		t.Fatalf("cancelled request got %d: %s", w.Code, w.Body.String())
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("cancelled result persisted, stat error %v", err)
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (fn roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return fn(r) }

func TestTranslationStructuredPayloadAndResult(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/chat/completions" || r.Method != "POST" {
			t.Errorf("upstream %s %s", r.Method, r.URL.Path)
		}
		if r.Header.Get("Authorization") != "Bearer test-upstream-key" {
			t.Error("missing upstream authorization")
		}
		var payload struct {
			Model    string `json:"model"`
			Messages []struct {
				Role    string `json:"role"`
				Content string `json:"content"`
			} `json:"messages"`
			ResponseFormat struct {
				Type   string `json:"type"`
				Schema struct {
					Strict bool           `json:"strict"`
					Schema map[string]any `json:"schema"`
				} `json:"json_schema"`
			} `json:"response_format"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Error(err)
		}
		if payload.Model != "test-text-model" || payload.ResponseFormat.Type != "json_schema" || !payload.ResponseFormat.Schema.Strict {
			t.Errorf("bad structured payload: %+v", payload)
		}
		if len(payload.Messages) != 2 || payload.Messages[0].Role != "system" || !strings.Contains(payload.Messages[1].Content, `"source_language":"de"`) || !strings.Contains(payload.Messages[1].Content, `"target_language":"ru"`) || !strings.Contains(payload.Messages[1].Content, `"text":"Hallo"`) {
			t.Errorf("bad messages: %+v", payload.Messages)
		}
		props, _ := payload.ResponseFormat.Schema.Schema["properties"].(map[string]any)
		for _, key := range []string{"translation", "idioms", "patterns", "vocabulary"} {
			if props[key] == nil {
				t.Errorf("missing schema %s", key)
			}
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"message": map[string]any{"content": translationFixture}}}})
	}))
	defer upstream.Close()
	cfg := &serverConfig{apiKey: "test-upstream-key", baseURL: upstream.URL, textModel: "test-text-model", authToken: "test-token", historyPath: filepath.Join(t.TempDir(), "history.json"), httpClient: upstream.Client()}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	w := translationRequest(h, http.MethodPost, `{"text":"Hallo","source_language":"de","target_language":"ru"}`, "test-token")
	if w.Code != http.StatusCreated {
		t.Fatalf("got %d: %s", w.Code, w.Body.String())
	}
	var got struct {
		ID          string `json:"id"`
		CreatedAt   string `json:"created_at"`
		Text        string `json:"text"`
		Source      string `json:"source_language"`
		Target      string `json:"target_language"`
		Translation string `json:"translation"`
		Idioms      []struct{ Expression, Meaning, Example string }
		Patterns    []struct{ Pattern, Explanation string }
		Vocabulary  []struct{ Word, Meaning string }
	}
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.ID == "" || got.Text != "Hallo" || got.Source != "de" || got.Target != "ru" || got.Translation != "Привет" || len(got.Idioms) != 1 || got.Idioms[0].Example != "Ich sage Hallo." || len(got.Patterns) != 1 || len(got.Vocabulary) != 1 {
		t.Fatalf("bad record: %+v", got)
	}
	if _, err := time.Parse(time.RFC3339, got.CreatedAt); err != nil {
		t.Fatal(err)
	}
}
