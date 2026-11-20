package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// No real credentials or upstream network. The actual authenticated Go handler
// serves real application assets; only the provider transport is synthetic.
func TestDictationAssessmentBrowserFixture(t *testing.T) {
	dir := os.Getenv("DICTATION_ASSESSMENT_BROWSER")
	if dir == "" {
		t.Skip("local browser fixture only")
	}
	f := newAssessmentFixture(t)
	seedDictationAssessment(t, f)
	if e := f.cfg.dictationTransaction(f.owner, true, func(d *dictationData) error {
		v := dictationFind(d, "dict")
		v.Text = "Die kleine Katze schläft. " + strings.Repeat("Danach gehen die Kinder zusammen in die große Schule. ", 6)
		v.Plan = dictationPlan(v.Text)
		return nil
	}); e != nil {
		t.Fatal(e)
	}
	f.reply = func(r *http.Request) (string, error) {
		var body struct {
			Input []struct {
				Content string `json:"content"`
			} `json:"input"`
		}
		if e := json.NewDecoder(r.Body).Decode(&body); e != nil {
			return "", e
		}
		var input struct {
			Answer    string             `json:"answer"`
			Alignment dictationAlignment `json:"alignment"`
		}
		if len(body.Input) != 1 {
			return "", errors.New("fixture input")
		}
		json.Unmarshal([]byte(body.Input[0].Content), &input)
		time.Sleep(3 * time.Second)
		if strings.Contains(input.Answer, "Fehler") {
			return "", errors.New("synthetic provider failure")
		}
		result := dictationAssessmentResult{Notes: []dictationAssessmentNote{}}
		for _, s := range input.Alignment.Spans {
			if s.Kind != "equal" && s.Kind != "unattempted" {
				result.Notes = append(result.Notes, dictationAssessmentNote{s.ID, "grammar", s.Original, s.Written, "Synthetic provider explanation for UI testing only. <img src=x onerror=alert(1)> The reference remains unchanged."})
				break
			}
		}
		b, _ := json.Marshal(result)
		return accountTranslationSSE(string(b), true, "response.completed"), nil
	}
	srv := httptest.NewServer(f.h)
	t.Setenv("WEB_ORIGIN", strings.Replace(srv.URL, "127.0.0.1", "localhost", 1))
	defer srv.Close()
	browser, e := f.cfg.auth.store.createBrowser(f.token, f.owner, time.Now())
	if e != nil {
		t.Fatal(e)
	}
	if e = os.MkdirAll(dir, 0700); e != nil {
		t.Fatal(e)
	}
	info, _ := json.Marshal(map[string]string{"url": strings.Replace(srv.URL, "127.0.0.1", "localhost", 1), "browser": browser})
	if e = os.WriteFile(filepath.Join(dir, "fixture.json"), info, 0600); e != nil {
		t.Fatal(e)
	}
	deadline := time.Now().Add(5 * time.Minute)
	for time.Now().Before(deadline) {
		if _, e = os.Stat(filepath.Join(dir, "done")); e == nil {
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatal("browser fixture timed out")
}
func TestDictationAssessmentWireFixtures(t *testing.T) {
	f := newAssessmentFixture(t)
	seedDictationAssessment(t, f)
	records := []json.RawMessage{}
	capture := func() {
		w := dictationAssessmentCall(f, "GET", "/dict", "")
		if w.Code != 200 {
			t.Fatal(w.Code)
		}
		records = append(records, append(json.RawMessage{}, w.Body.Bytes()...))
	}
	capture()
	f.reply = func(*http.Request) (string, error) {
		capture()
		return accountTranslationSSE(`{"notes":[]}`, true, "response.completed"), nil
	}
	w := dictationAssessmentCall(f, "POST", "/dict/check", `{"revision":1,"hybrid":true}`)
	if w.Code != 200 {
		t.Fatal(w.Code)
	}
	capture()
	// A second actual handler instance produces failure; no invented DTO fixtures.
	f2 := newAssessmentFixture(t)
	seedDictationAssessment(t, f2)
	f2.reply = func(*http.Request) (string, error) { return "", errors.New("synthetic timeout") }
	w = dictationAssessmentCall(f2, "POST", "/dict/check", `{"revision":1,"hybrid":true}`)
	if w.Code != 200 {
		t.Fatal(w.Code)
	}
	records = append(records, append(json.RawMessage{}, w.Body.Bytes()...))
	if path := os.Getenv("DICTATION_ASSESSMENT_FIXTURE"); path != "" {
		b, _ := json.Marshal(records)
		if e := os.WriteFile(path, b, 0600); e != nil {
			t.Fatal(e)
		}
	}
}
