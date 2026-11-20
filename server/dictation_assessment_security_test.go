package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestDictationAssessmentRevocationDuplicateAndOwnerIsolation(t *testing.T) {
	for _, mode := range []string{"revocation", "duplicate", "owner"} {
		t.Run(mode, func(t *testing.T) {
			f := newAssessmentFixture(t)
			seedDictationAssessment(t, f)
			started, release := make(chan struct{}), make(chan struct{})
			f.reply = func(*http.Request) (string, error) {
				close(started)
				<-release
				return accountTranslationSSE(`{"notes":[]}`, true, "response.completed"), nil
			}
			done := make(chan *httptest.ResponseRecorder, 1)
			go func() { done <- dictationAssessmentCall(f, "POST", "/dict/check", `{"revision":1,"hybrid":true}`) }()
			<-started
			switch mode {
			case "duplicate":
				w := dictationAssessmentCall(f, "POST", "/dict/check", `{"revision":1,"hybrid":true}`)
				if w.Code != 200 || !strings.Contains(w.Body.String(), `"state":"pending"`) {
					t.Fatal(w.Code, w.Body.String())
				}
			case "revocation":
				if e := f.cfg.auth.store.lock.locked(func() error {
					d, e := f.cfg.auth.store.read()
					if e != nil {
						return e
					}
					delete(d.Sessions, sessionHash(f.token))
					return f.cfg.auth.store.write(d)
				}); e != nil {
					t.Fatal(e)
				}
			case "owner":
				token, _, e := f.cfg.auth.store.create("other", time.Now())
				if e != nil {
					t.Fatal(e)
				}
				r := httptest.NewRequest("GET", "/v1/learning/dictations/dict", nil)
				r.Header.Set("Authorization", "Bearer "+token)
				w := httptest.NewRecorder()
				f.h.ServeHTTP(w, r)
				if w.Code != 404 || strings.Contains(w.Body.String(), "Katze") {
					t.Fatal(w.Code, w.Body.String())
				}
			}
			close(release)
			w := <-done
			if mode == "revocation" && w.Code != 401 {
				t.Fatal(w.Code)
			}
			if f.calls.Load() != 1 {
				t.Fatal("duplicate dispatch", f.calls.Load())
			}
			if e := f.cfg.dictationTransaction(f.owner, false, func(d *dictationData) error {
				a := dictationFind(d, "dict").Assessment
				if mode == "revocation" && a.Result != nil {
					t.Error("late result persisted after revocation")
				}
				if a.Answer != "Die Katze schläft." {
					t.Error("raw answer erased")
				}
				return nil
			}); e != nil {
				t.Fatal(e)
			}
		})
	}
}
func TestDictationAssessmentCatalogCancellationAndNoFallback(t *testing.T) {
	for _, mode := range []string{"missing-model", "cancel"} {
		t.Run(mode, func(t *testing.T) {
			f := newAssessmentFixture(t)
			seedDictationAssessment(t, f)
			f.cfg.provider.client = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
				if !strings.Contains(r.URL.Path, "models") {
					t.Error("unexpected inference/fallback")
				}
				// Even catalog preflight sees the durable literal receipt.
				w := dictationAssessmentCall(f, "GET", "/dict", "")
				if !strings.Contains(w.Body.String(), `"state":"pending"`) {
					t.Error("no durable preflight receipt")
				}
				slug := "other"
				if mode == "cancel" {
					slug = coachModel
					w = dictationAssessmentCall(f, "POST", "/dict/cancel-assessment", `{"revision":1}`)
					if w.Code != 200 {
						t.Error(w.Code)
					}
				}
				return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(`{"models":[{"slug":"` + slug + `","visibility":"list"}]}`))}, nil
			})}
			w := dictationAssessmentCall(f, "POST", "/dict/check", `{"revision":1,"hybrid":true}`)
			if w.Code != 200 {
				t.Fatal(w.Code, w.Body.String())
			}
			if mode == "missing-model" && !strings.Contains(w.Body.String(), `"error":"model_unavailable"`) {
				t.Fatal(w.Body.String())
			}
			if mode == "cancel" && !strings.Contains(w.Body.String(), `"state":"canceled"`) {
				t.Fatal(w.Body.String())
			}
		})
	}
}
func TestDictationAssessmentQuotaDistinctFromSpeech(t *testing.T) {
	t.Setenv("TRANSLATION_DAILY_ATTEMPTS", "1")
	f := newAssessmentFixture(t)
	seedDictationAssessment(t, f)
	f.reply = func(*http.Request) (string, error) {
		return accountTranslationSSE(`{"notes":[]}`, true, "response.completed"), nil
	}
	w := dictationAssessmentCall(f, "POST", "/dict/check", `{"revision":1,"hybrid":true}`)
	if w.Code != 200 {
		t.Fatal(w.Code)
	}
	for _, v := range []struct{ method, path, body string }{{"POST", "/dict/attempts", `{"id":"second"}`}, {"PUT", "/second", `{"revision":0,"mode":"whole","draft":"Die Katze schläft."}`}} {
		w = dictationAssessmentCall(f, v.method, v.path, v.body)
		if w.Code != 200 {
			t.Fatal(w.Code, w.Body.String())
		}
	}
	w = dictationAssessmentCall(f, "POST", "/second/check", `{"revision":1,"hybrid":true}`)
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"error":"llm_quota"`) || !strings.Contains(w.Body.String(), `"alignment"`) {
		t.Fatal(w.Code, w.Body.String())
	}
	if f.calls.Load() != 1 {
		t.Fatal("quota bypass", f.calls.Load())
	}
}
