package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func dictationAssessmentCall(f *assessmentFixture, method, path, body string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, "/v1/learning/dictations"+path, strings.NewReader(body))
	r.Header.Set("Authorization", "Bearer "+f.token)
	w := httptest.NewRecorder()
	f.h.ServeHTTP(w, r)
	return w
}
func seedDictationAssessment(t *testing.T, f *assessmentFixture) {
	t.Helper()
	for _, v := range []struct{ method, path, body string }{{"POST", "", `{"id":"dict","title":"Synthetic","text":"Die kleine Katze schläft. Danach geht sie heim.","language":"de"}`}, {"PUT", "/dict", `{"revision":0,"mode":"whole","draft":"Die Katze schläft."}`}} {
		w := dictationAssessmentCall(f, v.method, v.path, v.body)
		if w.Code != 200 {
			t.Fatal(w.Code, w.Body.String())
		}
	}
}
func TestDictationHybridFailureRecoveryAndNoAutomaticInference(t *testing.T) {
	f := newAssessmentFixture(t)
	seedDictationAssessment(t, f)
	f.reply = func(*http.Request) (string, error) { return "", errors.New("synthetic timeout") }
	for i := 0; i < 2; i++ {
		w := dictationAssessmentCall(f, "POST", "/dict/check", `{"revision":1,"hybrid":true}`)
		if w.Code != 200 || !strings.Contains(w.Body.String(), `"state":"failed"`) || !strings.Contains(w.Body.String(), `"alignment"`) {
			t.Fatal(w.Code, w.Body.String())
		}
	}
	for i := 0; i < 2; i++ {
		dictationAssessmentCall(f, "GET", "/dict", "")
	}
	if f.calls.Load() != 1 {
		t.Fatal(f.calls.Load())
	}
	if w := dictationAssessmentCall(f, "PUT", "/dict", `{"mode":"whole","revision":2,"draft":"overwrite"}`); w.Code != 409 {
		t.Fatal(w.Code)
	}
	f.h, _ = newHandler(f.cfg)
	w := dictationAssessmentCall(f, "GET", "/dict", "")
	if !strings.Contains(w.Body.String(), `"answer":"Die Katze schläft."`) {
		t.Fatal(w.Body.String())
	}
}
func TestDictationHybridCancelAndLateResult(t *testing.T) {
	for _, before := range []bool{true, false} {
		t.Run(map[bool]string{true: "before", false: "during"}[before], func(t *testing.T) {
			f := newAssessmentFixture(t)
			seedDictationAssessment(t, f)
			entered, release := make(chan struct{}), make(chan struct{})
			f.reply = func(*http.Request) (string, error) {
				close(entered)
				<-release
				return accountTranslationSSE(`{"notes":[]}`, true, "response.completed"), nil
			}
			if before {
				w := dictationAssessmentCall(f, "POST", "/dict/cancel-assessment", `{"revision":1}`)
				if w.Code != 200 {
					t.Fatal(w.Code)
				}
			}
			done := make(chan *httptest.ResponseRecorder, 1)
			go func() { done <- dictationAssessmentCall(f, "POST", "/dict/check", `{"revision":1,"hybrid":true}`) }()
			if !before {
				select {
				case <-entered:
				case <-time.After(3 * time.Second):
					t.Fatal("inference did not start")
				}
				w := dictationAssessmentCall(f, "POST", "/dict/cancel-assessment", `{"revision":1}`)
				if w.Code != 200 {
					t.Fatal(w.Code)
				}
				close(release)
			}
			w := <-done
			if w.Code != 200 || !strings.Contains(w.Body.String(), `"state":"canceled"`) || strings.Contains(w.Body.String(), `"result"`) {
				t.Fatal(w.Code, w.Body.String())
			}
			if before && f.calls.Load() != 0 {
				t.Fatal("canceled preflight sent")
			}
		})
	}
}
func TestDictationHybridRejectUngroundedNotes(t *testing.T) {
	a := dictationAlign("Die Katze schläft. Danach geht sie heim.", "Die Katze schläft.", false)
	for _, raw := range []string{`{"notes":[{"span_id":"s1","category":"grammar","source_quote":" Danach geht sie heim.","answer_quote":"","explanation":"Must not grade suffix"}]}`, `{"notes":[{"span_id":"s0","category":"grammar","source_quote":"rewritten","answer_quote":"Die Katze schläft.","explanation":"Bad quote"}]}`, `{"notes":null}`, `{"notes":[],"notes":[]}`, `{"notes":[]} {}`} {
		if _, e := decodeDictationAssessment(raw, a); e == nil {
			t.Fatal("accepted", raw)
		}
	}
	if _, e := decodeDictationAssessment(`{"notes":[]}`, a); e != nil {
		t.Fatal(e)
	}
}
func TestDictationHybridReceiptBeforeNetworkAndDuplicate(t *testing.T) {
	f := newAssessmentFixture(t)
	seedDictationAssessment(t, f)
	f.reply = func(r *http.Request) (string, error) {
		var data map[string]any
		json.NewDecoder(r.Body).Decode(&data)
		if data["model"] != coachModel {
			t.Fatal(data["model"])
		}
		w := dictationAssessmentCall(f, "GET", "/dict", "")
		if !strings.Contains(w.Body.String(), `"state":"pending"`) || !strings.Contains(w.Body.String(), `"answer":"Die Katze schläft."`) {
			t.Fatal("receipt must precede inference", w.Body.String())
		}
		return accountTranslationSSE(`{"notes":[{"span_id":"s1","category":"omission","source_quote":" kleine","answer_quote":"","explanation":"The adjective is missing; the remaining sentence is grammatical."}]}`, true, "response.completed"), nil
	}
	for i := 0; i < 2; i++ {
		w := dictationAssessmentCall(f, "POST", "/dict/check", `{"revision":1,"hybrid":true,"locale":"en"}`)
		if w.Code != 200 || !strings.Contains(w.Body.String(), `"state":"completed"`) || !strings.Contains(w.Body.String(), `"unattempted_words":4`) {
			t.Fatal(w.Code, w.Body.String())
		}
	}
	if f.calls.Load() != 1 {
		t.Fatal("duplicate inference", f.calls.Load())
	}
}
