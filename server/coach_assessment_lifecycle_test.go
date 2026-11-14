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
	"sync/atomic"
	"testing"
	"time"
)

type assessmentFixture struct {
	cfg          *serverConfig
	h            http.Handler
	token, owner string
	calls        atomic.Int32
	reply        func(*http.Request) (string, error)
}

func newAssessmentFixture(t *testing.T) *assessmentFixture {
	t.Helper()
	key := filepath.Join(t.TempDir(), "key")
	if e := os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600); e != nil {
		t.Fatal(e)
	}
	t.Setenv("PROVIDER_KEY_FILE", key)
	dir := t.TempDir()
	f := &assessmentFixture{}
	f.cfg = &serverConfig{authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json")}
	f.reply = func(*http.Request) (string, error) {
		return accountTranslationSSE(`{"verdict":"correct","corrected_answer":"Ich warte auf den Bus.","explanation":"Equivalent full sentence.","uncertainty_reason":""}`, true, "response.completed"), nil
	}
	f.cfg.httpClient = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		text := `{"models":[{"slug":"gpt-6.1-terra","visibility":"list"}]}`
		if !strings.Contains(r.URL.Path, "models") {
			f.calls.Add(1)
			var e error
			text, e = f.reply(r)
			if e != nil {
				return nil, e
			}
		}
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(text))}, nil
	})}
	var e error
	f.h, e = newHandler(f.cfg)
	if e != nil {
		t.Fatal(e)
	}
	token, s, e := f.cfg.auth.store.create("assessment-owner", time.Now())
	if e != nil {
		t.Fatal(e)
	}
	f.token = token
	f.owner = s.UserID
	if e = f.cfg.provider.save(f.owner, providerCredential{AccessToken: "synthetic", Expires: time.Now().Add(time.Hour)}); e != nil {
		t.Fatal(e)
	}
	history, e := openHistory(filepath.Join(dir, "users", sessionHash(f.owner)+".json"))
	if e != nil {
		t.Fatal(e)
	}
	if e = history.append(translationRecord{ID: "original", translationInput: translationInput{TargetLanguage: "de"}, translationResult: translationResult{Translation: "Ich warte auf den Bus."}}); e != nil {
		t.Fatal(e)
	}
	f.addTurn(t, "one")
	return f
}
func (f *assessmentFixture) addTurn(t *testing.T, id string) {
	t.Helper()
	if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error {
		d.Turns = append(d.Turns, coachTurn{ID: id, State: "completed", Language: "de", Result: &coachResult{Kind: "short_rephrase", Prompt: "Express that you are waiting for the bus.", Target: "verb_government.preposition_case", SourceID: "translation:original", Quote: "Ich warte auf den Bus.", Answers: []string{"auf"}}})
		return nil
	}); e != nil {
		t.Fatal(e)
	}
}
func (f *assessmentFixture) call(in coachInput) *httptest.ResponseRecorder {
	b, _ := json.Marshal(in)
	r := httptest.NewRequest("POST", "/v1/learning/coach", strings.NewReader(string(b)))
	r.Header.Set("Authorization", "Bearer "+f.token)
	w := httptest.NewRecorder()
	f.h.ServeHTTP(w, r)
	return w
}
func (f *assessmentFixture) read(t *testing.T) coachData {
	t.Helper()
	var data coachData
	if e := f.cfg.coachStore(f.owner).transaction(false, func(d *coachData) error { data = *d; return nil }); e != nil {
		t.Fatal(e)
	}
	return data
}
func answerInput() coachInput {
	return coachInput{RequestID: "check", Action: "answer", TurnID: "one", Text: "Ich warte auf den Bus.", Locale: "en"}
}

func TestAssessmentStrictResultsAndInfrastructureSeparation(t *testing.T) {
	for _, tc := range []struct {
		name, raw, verdict string
		fail               bool
	}{
		{"equivalent", `{"verdict":"correct","corrected_answer":"Ich warte auf den Bus.","explanation":"Valid equivalent wording.","uncertainty_reason":""}`, "correct", false},
		{"partial", `{"verdict":"partially_correct","corrected_answer":"Ich warte auf den Bus.","explanation":"The preposition is right; the noun case needs correction.","uncertainty_reason":""}`, "partially_correct", false},
		{"ambiguity", `{"verdict":"uncertain","corrected_answer":"","explanation":"The requested referent is not specified.","uncertainty_reason":"ambiguous_exercise"}`, "uncertain", false},
		{"missingcontext", `{"verdict":"uncertain","corrected_answer":"","explanation":"The antecedent is missing.","uncertainty_reason":"insufficient_context"}`, "uncertain", false},
		{"listabsence", `{"verdict":"uncertain","corrected_answer":"","explanation":"Not in list.","uncertainty_reason":"unlisted"}`, "", true},
		{"inventedskill", `{"verdict":"correct","corrected_answer":"auf","explanation":"ok","uncertainty_reason":"","target":"new.skill"}`, "", true},
		{"citation", `{"verdict":"correct","corrected_answer":"auf","explanation":"ok","uncertainty_reason":"","source_id":"foreign"}`, "", true},
		{"duplicatekey", `{"verdict":"correct","verdict":"incorrect","corrected_answer":"auf","explanation":"ok","uncertainty_reason":""}`, "", true},
		{"trailing", `{"verdict":"correct","corrected_answer":"auf","explanation":"ok","uncertainty_reason":""} {}`, "", true},
		{"null", `{"verdict":"correct","corrected_answer":null,"explanation":"ok","uncertainty_reason":""}`, "", true},
		{"emptycorrection", `{"verdict":"incorrect","corrected_answer":"","explanation":"ok","uncertainty_reason":""}`, "", true},
		{"malformed", `not JSON`, "", true},
		{"refusal", "refusal", "", true},
		{"timeout", "timeout", "", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := newAssessmentFixture(t)
			f.reply = func(r *http.Request) (string, error) {
				if tc.raw == "timeout" {
					return "", context.DeadlineExceeded
				}
				if tc.raw == "refusal" {
					return "data: {\"type\":\"response.refusal.done\"}\n\n", nil
				}
				return accountTranslationSSE(tc.raw, true, "response.completed"), nil
			}
			w := f.call(answerInput())
			if w.Code != 200 {
				t.Fatal(w.Code, w.Body.String())
			}
			d := f.read(t)
			a := coachFind(&d, "one").Attempt
			if a.Answer != answerInput().Text || f.calls.Load() != 1 {
				t.Fatal(a, f.calls.Load())
			}
			if tc.fail {
				if a.AssessmentState != "failed" || a.Assessment != nil || len(coachView(&d)["observations"].([]coachObservation)) != 0 {
					t.Fatal("infrastructure became learner evidence", a)
				}
			} else if a.AssessmentState != "completed" || a.Assessment.Verdict != tc.verdict {
				t.Fatal(a)
			}
			if w = f.call(answerInput()); w.Code != 200 || f.calls.Load() != 1 {
				t.Fatal("automatic repeat", w.Code, f.calls.Load())
			}
		})
	}
}
func TestAssessmentDoubleTapCancelRevocationAndQuota(t *testing.T) {
	for _, mode := range []string{"duplicate", "cancel", "revocation", "old-owner"} {
		t.Run(mode, func(t *testing.T) {
			f := newAssessmentFixture(t)
			started, release := make(chan struct{}), make(chan struct{})
			original := f.reply
			f.reply = func(r *http.Request) (string, error) { close(started); <-release; return original(r) }
			done := make(chan *httptest.ResponseRecorder, 1)
			go func() { done <- f.call(answerInput()) }()
			<-started
			d := f.read(t)
			a := coachFind(&d, "one").Attempt
			if a.Answer != answerInput().Text || a.AssessmentState != "pending" || len(coachView(&d)["observations"].([]coachObservation)) != 0 {
				t.Fatal("pending not durable", a)
			}
			switch mode {
			case "duplicate":
				for _, id := range []string{"check", "second-tap"} {
					in := answerInput()
					in.RequestID = id
					if w := f.call(in); w.Code != 200 {
						t.Fatal(w.Code, w.Body.String())
					}
				}
			case "cancel":
				if w := f.call(coachInput{RequestID: "cancel", Action: "cancel", TurnID: "one", Locale: "en"}); w.Code != 200 {
					t.Fatal(w.Code)
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
			case "old-owner":
				token, _, e := f.cfg.auth.store.create("other", time.Now())
				if e != nil {
					t.Fatal(e)
				}
				b, _ := json.Marshal(answerInput())
				r := httptest.NewRequest("POST", "/v1/learning/coach", strings.NewReader(string(b)))
				r.Header.Set("Authorization", "Bearer "+token)
				w := httptest.NewRecorder()
				f.h.ServeHTTP(w, r)
				if w.Code != 409 {
					t.Fatal("foreign turn", w.Code)
				}
			}
			close(release)
			w := <-done
			if mode == "revocation" && w.Code != 401 {
				t.Fatal(w.Code)
			}
			d = f.read(t)
			a = coachFind(&d, "one").Attempt
			if (mode == "cancel" || mode == "revocation") && a.Assessment != nil {
				t.Fatal("late result committed")
			}
			if f.calls.Load() != 1 {
				t.Fatal("duplicate upstream", f.calls.Load())
			}
			b, e := os.ReadFile(filepath.Join(f.cfg.provider.dir, "quotas", sessionHash(f.owner)+".json"))
			if e != nil {
				t.Fatal(e)
			}
			var q dailyTranslationQuota
			if e = json.Unmarshal(b, &q); e != nil || q.Attempts != 1 {
				t.Fatal(string(b), e)
			}
		})
	}
}
func TestAssessmentCancelBeforeAdmission(t *testing.T) {
	f := newAssessmentFixture(t)
	// Cancel may overtake the answer POST on the network. The ID is its durable fence.
	if w := f.call(coachInput{RequestID: "cancel", Action: "cancel", TurnID: "check", Locale: "en"}); w.Code != 200 {
		t.Fatal(w.Code)
	}
	w := f.call(answerInput())
	if f.calls.Load() != 0 {
		t.Fatalf("canceled answer dispatched: %d %s", w.Code, w.Body.String())
	}
}
func TestAssessmentLateCanceledResultCannotOverwriteRecheck(t *testing.T) {
	f := newAssessmentFixture(t)
	started, release := make(chan struct{}), make(chan struct{})
	original := f.reply
	f.reply = func(r *http.Request) (string, error) { close(started); <-release; return original(r) }
	done := make(chan *httptest.ResponseRecorder, 1)
	go func() { done <- f.call(answerInput()) }()
	<-started
	if w := f.call(coachInput{RequestID: "cancel", Action: "cancel", TurnID: "check", Locale: "en"}); w.Code != 200 {
		t.Fatal(w.Code)
	}
	// Explicit recheck while the canceled upstream still owns quota fails admission,
	// but its durable attempt must never be replaced by the old response.
	if w := f.call(coachInput{RequestID: "recheck", Action: "recheck", TurnID: "one", Locale: "en"}); w.Code != 200 {
		t.Fatal(w.Code)
	}
	close(release)
	<-done
	d := f.read(t)
	a := coachFind(&d, "one").Attempt
	if a.ID != "recheck" || a.Assessment != nil || a.AssessmentState != "failed" || f.calls.Load() != 1 {
		t.Fatal(a, f.calls.Load())
	}
}
func TestAssessmentRecheckFailureKeepsPriorEvidence(t *testing.T) {
	f := newAssessmentFixture(t)
	if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error {
		coachFind(d, "one").Attempt = &coachAttempt{ID: "legacy", Answer: "auf", Outcome: "correct", OriginalOutcome: "correct", At: time.Now()}
		return nil
	}); e != nil {
		t.Fatal(e)
	}
	f.reply = func(*http.Request) (string, error) { return "", context.DeadlineExceeded }
	if w := f.call(coachInput{RequestID: "recheck", Action: "recheck", TurnID: "one", Locale: "en"}); w.Code != 200 {
		t.Fatal(w.Code)
	}
	d := f.read(t)
	o := coachView(&d)["observations"].([]coachObservation)
	if len(o) != 1 || o[0].Correct != 1 {
		t.Fatal("infrastructure failure changed prior evidence", o)
	}
}
func TestAssessmentAdmissionBudgetsOwnerAndSource(t *testing.T) {
	for _, mode := range []string{"budget", "owner", "source", "catalog", "repeated"} {
		t.Run(mode, func(t *testing.T) {
			f := newAssessmentFixture(t)
			in := answerInput()
			switch mode {
			case "budget":
				t.Setenv("TRANSLATION_DAILY_ATTEMPTS", "1")
				if w := f.call(in); w.Code != 200 {
					t.Fatal(w.Code)
				}
				f.addTurn(t, "two")
				in.TurnID = "two"
				in.RequestID = "two"
			case "owner":
				in.OwnerID = "old-owner"
			case "source":
				if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error { coachFind(d, "one").Result.SourceID = "translation:foreign"; return nil }); e != nil {
					t.Fatal(e)
				}
			case "catalog":
				f.cfg.provider.client = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
					if !strings.Contains(r.URL.Path, "models") {
						t.Error("fallback inference")
					}
					return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(`{"models":[{"slug":"other","visibility":"list"}]}`))}, nil
				})}
			case "repeated":
				if w := f.call(in); w.Code != 200 {
					t.Fatal(w.Code)
				}
				in.RequestID = "other-check"
			}
			before := f.calls.Load()
			w := f.call(in)
			if f.calls.Load() != before {
				t.Fatal("unexpected call", mode)
			}
			if mode == "owner" && w.Code != 409 {
				t.Fatal("owner fence", w.Code)
			}
			d := f.read(t)
			if mode == "catalog" && coachFind(&d, "one").Attempt.AssessmentError != "model_unavailable" {
				t.Fatal("exact catalog not enforced")
			}
		})
	}
}
func TestAssessmentPassageExcerptAndLiteralSourceID(t *testing.T) {
	cfg, h, token, _, j := learningFixture(t)
	s, e := cfg.auth.store.lookup(token, time.Now())
	if e != nil {
		t.Fatal(e)
	}
	if w := authCall(h, "PUT", "/v1/learning/episodes/"+j.ID+"/passages/0", `{"favorite":true}`, token); w.Code != 200 {
		t.Fatal(w.Code)
	}
	quote := j.Segments[0].Text
	turn := coachTurn{Language: j.SourceLanguage, Result: &coachResult{Kind: "cloze", Prompt: "___", Target: "grammar.case", SourceID: "passage:" + j.ID + ":0", Quote: string([]rune(quote)[:1])}}
	if _, e := cfg.coachAssessmentSource(s.UserID, turn); e != nil {
		t.Fatal("verified source excerpt rejected", e)
	}
	turn.Result.SourceID = "passage:" + j.ID + ":00"
	if _, e := cfg.coachAssessmentSource(s.UserID, turn); e == nil {
		t.Fatal("malformed index normalized")
	}
}
func TestAssessmentRecheckPreservesOriginalAndNoAutomaticInference(t *testing.T) {
	f := newAssessmentFixture(t)
	if e := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error {
		coachFind(d, "one").Attempt = &coachAttempt{ID: "old", Answer: "  beim  ", Outcome: "ambiguous", OriginalOutcome: "ambiguous", At: time.Now()}
		return nil
	}); e != nil {
		t.Fatal(e)
	}
	w := f.call(coachInput{RequestID: "recheck", Action: "recheck", TurnID: "one", Locale: "en"})
	if w.Code != 200 {
		t.Fatal(w.Code)
	}
	d := f.read(t)
	v := coachFind(&d, "one")
	if len(v.PriorAttempts) != 1 || v.PriorAttempts[0].Answer != "  beim  " || v.Attempt.Answer != "  beim  " || v.Attempt.Assisted {
		t.Fatal("original answer/assistance lost", v)
	}
}
