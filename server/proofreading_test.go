package main

import (
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestGermanProofreadingLegacyAndAccountContract(t *testing.T) {
	for _, account := range []bool{false, true} {
		t.Run(map[bool]string{false: "legacy", true: "account"}[account], func(t *testing.T) {
			t.Setenv("PROVIDER_KEY_FILE", filepath.Join(t.TempDir(), "key"))
			if err := os.WriteFile(os.Getenv("PROVIDER_KEY_FILE"), []byte(strings.Repeat("k", 32)), 0600); err != nil {
				t.Fatal(err)
			}
			calls := 0
			dir := t.TempDir()
			cfg := &serverConfig{authToken: "legacy", apiKey: "synthetic", baseURL: "https://fixture.invalid", authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json")}
			cfg.httpClient = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
				if strings.Contains(r.URL.Path, "models") {
					return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"models":[{"slug":"offered","visibility":"list"}]}`)), Header: http.Header{}}, nil
				}
				calls++
				var payload map[string]any
				if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
					t.Fatal(err)
				}
				trusted := ""
				user := ""
				if account {
					trusted = payload["instructions"].(string)
					msg := payload["input"].([]any)[0].(map[string]any)
					user = msg["content"].(string)
					format := payload["text"].(map[string]any)["format"].(map[string]any)
					if format["name"] != "translated_text" || format["strict"] != true {
						t.Error("account output schema changed")
					}
				} else {
					msgs := payload["messages"].([]any)
					trusted = msgs[0].(map[string]any)["content"].(string)
					user = msgs[1].(map[string]any)["content"].(string)
					if payload["response_format"].(map[string]any)["type"] != "json_schema" {
						t.Error("legacy schema changed")
					}
				}
				for _, required := range []string{"German", "proofread", "grammar", "natural", "meaning", "facts", "register", "lower priority"} {
					if !strings.Contains(trusted, required) {
						t.Errorf("trusted proofreading prompt missing %q: %s", required, trusted)
					}
				}
				if strings.Contains(trusted, "CUSTOM-FORMAL") || !strings.Contains(user, "CUSTOM-FORMAL") || !strings.Contains(user, `"target_language":"de"`) {
					t.Error("style/data boundary lost")
				}
				body := `{"choices":[{"message":{"content":"{\"translation\":\"Ich habe einen Hund.\",\"idioms\":[],\"patterns\":[],\"vocabulary\":[]}"}}]}`
				if account {
					body = accountTranslationSSE(`{"text":"Ich habe einen Hund."}`, true, "response.completed")
				}
				return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(body)), Header: http.Header{}}, nil
			})}
			h, err := newHandler(cfg)
			if err != nil {
				t.Fatal(err)
			}
			token := "legacy"
			if account {
				var s authSession
				token, s, err = cfg.auth.store.create("proofreading-owner", time.Now())
				if err != nil {
					t.Fatal(err)
				}
				if err = cfg.provider.save(s.UserID, providerCredential{AccessToken: "synthetic", Expires: time.Now().Add(time.Hour)}); err != nil {
					t.Fatal(err)
				}
			}
			w := translationRequest(h, "POST", `{"text":"Ich haben ein Hund.","source_language":"de","target_language":"de","instructions":"CUSTOM-FORMAL: formal Sie register."}`, token)
			if w.Code != 201 {
				t.Fatalf("proofreading %d %s", w.Code, w.Body.String())
			}
			if calls != 1 {
				t.Fatalf("upstream calls %d", calls)
			}
			var record translationRecord
			if err = json.Unmarshal(w.Body.Bytes(), &record); err != nil || record.Translation != "Ich habe einen Hund." || record.SourceLanguage != "de" || record.TargetLanguage != "de" {
				t.Fatalf("record %v %v", record, err)
			}
			if len(record.Idioms) != 0 || len(record.Patterns) != 0 || len(record.Vocabulary) != 0 {
				t.Fatal("proofreading added enrichment")
			}
			restarted, err := newHandler(&serverConfig{authToken: cfg.authToken, authPath: cfg.authPath, historyPath: cfg.historyPath})
			if err != nil {
				t.Fatal(err)
			}
			w = translationRequest(restarted, "GET", "", token)
			if w.Code != 200 || !strings.Contains(w.Body.String(), `"translation":"Ich habe einen Hund."`) || !strings.Contains(w.Body.String(), `"target_language":"de"`) {
				t.Fatalf("reopened %d %s", w.Code, w.Body.String())
			}
			w = translationRequest(h, "POST", `{"text":"Привет","source_language":"ru","target_language":"ru"}`, token)
			if w.Code != 400 || calls != 1 {
				t.Fatalf("ru-ru accepted %d", w.Code)
			}
		})
	}
}
