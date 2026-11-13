package main

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestCoachCancelAndRevocationFenceLateProvider(t *testing.T) {
	for _, mode := range []string{"cancel", "logout", "cancel_catalog"} {
		t.Run(mode, func(t *testing.T) {
			key := filepath.Join(t.TempDir(), "key")
			if e := os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600); e != nil {
				t.Fatal(e)
			}
			t.Setenv("PROVIDER_KEY_FILE", key)
			dir := t.TempDir()
			started := make(chan struct{})
			release := make(chan struct{})
			cfg := &serverConfig{authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json")}
			cfg.httpClient = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
				text := `{"models":[{"slug":"gpt-6.1-terra","visibility":"list"}]}`
				if mode == "cancel_catalog" && strings.Contains(r.URL.Path, "models") {
					close(started)
					<-release
				}
				if !strings.Contains(r.URL.Path, "models") {
					if mode == "cancel_catalog" {
						t.Error("inference after pre-admission cancel")
						return nil, context.Canceled
					}
					close(started)
					<-release
					text = accountTranslationSSE(`{"message":"Practice","kind":"cloze","prompt":"Ich warte ___ den Bus.","target":"verb_government.preposition_case","source_id":"translation:original","quote":"Ich warte auf den Bus.","answers":["auf"],"incorrect_answers":[],"explanation":"warten auf"}`, true, "response.completed")
				}
				return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(text))}, nil
			})}
			h, e := newHandler(cfg)
			if e != nil {
				t.Fatal(e)
			}
			token, s, e := cfg.auth.store.create("owner", time.Now())
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
			if e = history.append(translationRecord{ID: "original", translationInput: translationInput{Text: "Wait", SourceLanguage: "en", TargetLanguage: "de"}, translationResult: translationResult{Translation: "Ich warte auf den Bus."}}); e != nil {
				t.Fatal(e)
			}
			call := func(path, body string) *httptest.ResponseRecorder {
				r := httptest.NewRequest("POST", path, strings.NewReader(body))
				r.Header.Set("Authorization", "Bearer "+token)
				w := httptest.NewRecorder()
				h.ServeHTTP(w, r)
				return w
			}
			done := make(chan *httptest.ResponseRecorder, 1)
			go func() {
				done <- call("/v1/learning/coach", `{"request_id":"one","action":"message","text":"Practice","locale":"en"}`)
			}()
			<-started
			if strings.HasPrefix(mode, "cancel") {
				if w := call("/v1/learning/coach", `{"request_id":"cancel-one","action":"cancel","turn_id":"one","locale":"en"}`); w.Code != 200 {
					t.Fatal(w.Code, w.Body.String())
				}
			} else {
				// Exercise the same auth-store lock used by actual logout.
				e = cfg.auth.store.lock.locked(func() error {
					d, e := cfg.auth.store.read()
					if e != nil {
						return e
					}
					delete(d.Sessions, sessionHash(token))
					return cfg.auth.store.write(d)
				})
				if e != nil {
					t.Fatal(e)
				}
			}
			close(release)
			w := <-done
			if mode == "logout" && w.Code != 401 {
				t.Fatalf("late logged-out write %d", w.Code)
			}
			e = cfg.coachStore(s.UserID).transaction(false, func(d *coachData) error {
				v := coachFind(d, "one")
				if v == nil || v.Result != nil {
					t.Fatal("late provider result committed")
				}
				if mode == "cancel" && v.State != "canceled" {
					t.Fatal(v.State)
				}
				return nil
			})
			if e != nil {
				t.Fatal(e)
			}
		})
	}
}
