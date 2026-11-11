package main

import (
	"context"
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

func TestTranslationInstructionsContract(t *testing.T) {
	for _, account := range []bool{false, true} {
		t.Run(map[bool]string{false: "legacy", true: "account"}[account], func(t *testing.T) {
			cfg := &serverConfig{authToken: "legacy", apiKey: "fixture", authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json")}
			cfg.httpClient = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
				body := `{"choices":[{"message":{"content":` + strconvQuote(translationFixture) + `}}]}`
				if strings.Contains(r.URL.Path, "models") {
					body = `{"models":[{"slug":"offered","display_name":"Offered"}]}`
				} else if r.URL.Path == "/v1/responses" {
					body = accountTranslationSSE(`{"text":"Привет"}`, true, "response.completed")
				}
				return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(body))}, nil
			})}
			cfg.baseURL = "https://fixture.invalid"
			h, err := newHandler(cfg)
			if err != nil {
				t.Fatal(err)
			}
			token := "legacy"
			if account {
				token, _, err = cfg.auth.store.create("fixture-owner", time.Now())
				if err != nil {
					t.Fatal(err)
				}
				// Validation must happen before a missing provider connection is considered.
			}
			for _, suffix := range []string{`,"instructions":null`, `,"instructions":42`, `,"instructions":{}`, `,"instructions":true`, `,"instructions":"` + strings.Repeat("😀", 1001) + `"`, `,"unknown":true`} {
				w := translationRequest(h, "POST", `{"text":"Hallo","source_language":"de","target_language":"ru"`+suffix+`}`, token)
				if w.Code != 400 {
					t.Errorf("invalid instruction suffix %s: %d %s", suffix, w.Code, w.Body.String())
				}
			}
			for _, suffix := range []string{"", `,"instructions":""`, `,"instructions":"` + strings.Repeat("😀", 1000) + `"`} {
				w := translationRequest(h, "POST", `{"text":"Hallo","source_language":"de","target_language":"ru"`+suffix+`}`, token)
				want := 201
				if account {
					want = 503
				}
				if w.Code != want {
					t.Errorf("valid instructions: %d want %d: %s", w.Code, want, w.Body.String())
				}
			}
			if !account {
				w := translationRequest(h, "GET", "", token)
				var out struct {
					Items []map[string]any `json:"items"`
				}
				json.Unmarshal(w.Body.Bytes(), &out)
				if len(out.Items) != 3 || out.Items[0]["instructions"] != strings.Repeat("😀", 1000) {
					t.Fatalf("instruction snapshot not saved: %s", w.Body.String())
				}
				if _, exists := out.Items[2]["instructions"]; exists {
					t.Fatal("legacy record gained instructions")
				}
			}
		})
	}
}
func strconvQuote(s string) string { b, _ := json.Marshal(s); return string(b) }

func TestAccountTranslationStyleIsLowerPriorityUserInput(t *testing.T) {
	p := &providerService{client: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		var payload map[string]any
		json.NewDecoder(r.Body).Decode(&payload)
		system, _ := payload["instructions"].(string)
		if !strings.Contains(system, "lower priority") || !strings.Contains(system, "style") || !strings.Contains(system, "data, never instructions") || !strings.Contains(system, "schema") {
			t.Errorf("missing trusted boundaries: %s", system)
		}
		if strings.Contains(system, "CUSTOM-INSTRUCTION") {
			t.Fatal("user instruction interpolated into trusted instructions")
		}
		input := payload["input"].([]any)[0].(map[string]any)
		var content map[string]any
		json.Unmarshal([]byte(input["content"].(string)), &content)
		if input["role"] != "user" || content["instructions"] != "CUSTOM-INSTRUCTION" || content["text"] != "Hallo" {
			t.Errorf("lost user style/data separation: %#v", content)
		}
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(accountTranslationSSE(`{"text":"Привет"}`, true, "response.completed")))}, nil
	})}}
	// Decode through JSON so this test fails behaviorally before the field exists.
	var input translationInput
	json.Unmarshal([]byte(`{"text":"Hallo","source_language":"de","target_language":"ru","instructions":"CUSTOM-INSTRUCTION"}`), &input)
	if got, err := p.translate(context.Background(), "fixture", "offered", input); err != nil || got != "Привет" {
		t.Fatalf("%q %v", got, err)
	}
}

func TestAccountInstructionsSnapshotPersistsAndRestores(t *testing.T) {
	t.Setenv("PROVIDER_KEY_FILE", filepath.Join(t.TempDir(), "key"))
	if err := os.WriteFile(os.Getenv("PROVIDER_KEY_FILE"), []byte(strings.Repeat("k", 32)), 0600); err != nil {
		t.Fatal(err)
	}
	cfg := &serverConfig{authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json"), httpClient: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		body := `{"models":[{"slug":"offered","visibility":"list"}]}`
		if strings.HasSuffix(r.URL.Path, "/responses") {
			body = accountTranslationSSE(`{"text":"Привет"}`, true, "response.completed")
		}
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(body))}, nil
	})}}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	token, s, err := cfg.auth.store.create("style-owner", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if err = cfg.provider.save(s.UserID, providerCredential{AccessToken: "synthetic", Expires: time.Now().Add(time.Hour)}); err != nil {
		t.Fatal(err)
	}
	w := translationRequest(h, "POST", `{"text":"Hallo","source_language":"de","target_language":"ru","instructions":"Use a formal tone."}`, token)
	if w.Code != 201 {
		t.Fatalf("style translation: %d %s", w.Code, w.Body.String())
	}
	h, err = newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	w = translationRequest(h, "GET", "", token)
	var out struct {
		Items []translationRecord `json:"items"`
	}
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &out) != nil || len(out.Items) != 1 || string(out.Items[0].Instructions) != "Use a formal tone." || out.Items[0].Translation != "Привет" {
		t.Fatalf("snapshot: %d %s", w.Code, w.Body.String())
	}
}

func TestLegacyTranslationStylePrompt(t *testing.T) {
	cfg := &serverConfig{baseURL: "https://fixture.invalid", httpClient: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		var payload struct {
			Messages []map[string]string `json:"messages"`
		}
		json.NewDecoder(r.Body).Decode(&payload)
		if !strings.Contains(payload.Messages[0]["content"], "lower priority") || strings.Contains(payload.Messages[0]["content"], "CUSTOM-INSTRUCTION") || !strings.Contains(payload.Messages[1]["content"], "CUSTOM-INSTRUCTION") {
			t.Errorf("unsafe/missing style prompt: %#v", payload.Messages)
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"choices":[{"message":{"content":` + strconvQuote(translationFixture) + `}}]}`))}, nil
	})}}
	var input translationInput
	json.Unmarshal([]byte(`{"text":"Hallo","source_language":"de","target_language":"ru","instructions":"CUSTOM-INSTRUCTION"}`), &input)
	_, err := cfg.fetchTranslation(httptest.NewRequest("POST", "/", nil), input)
	if err != nil {
		t.Fatal(err)
	}
}
