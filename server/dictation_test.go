package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDictationDurableOwner(t *testing.T) {
	t.Setenv("WEB_ORIGIN", "https://example.com")
	dir := t.TempDir()
	cfg := &serverConfig{authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json")}
	h, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	token, s, _ := cfg.auth.store.create("dictation-owner", time.Now())
	browser, _ := cfg.auth.store.createBrowser(token, s.UserID, time.Now())
	call := func(method, path, body string, csrf bool) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, "/v1/learning/dictations"+path, strings.NewReader(body))
		r.AddCookie(&http.Cookie{Name: browserCookie, Value: browser})
		r.Header.Set("Origin", "https://example.com")
		if csrf {
			r.Header.Set("X-CSRF-Token", browserCSRF(browser))
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	body := `{"id":"test-one","title":"Übung","text":"Dr. Müller geht heim. Morgen regnet es.","language":"de"}`
	if w := call("POST", "", body, false); w.Code != 403 {
		t.Fatal("CSRF", w.Code)
	}
	for i := 0; i < 2; i++ {
		if w := call("POST", "", body, true); w.Code != 200 {
			t.Fatalf("create %d %s", w.Code, w.Body.String())
		}
	}
	if w := call("GET", "", "", false); w.Code != 200 || strings.Count(w.Body.String(), `"id":"test-one"`) != 1 || strings.Contains(w.Body.String(), "Müller") {
		t.Fatal("list must hide original", w.Code, w.Body.String())
	}
	if w := call("PUT", "/test-one", `{"mode":"sentences","step":1,"replays":2,"draft":"Müller geht","revision":0}`, true); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	if w := call("POST", "/test-one/audio/0", `{}`, true); w.Code != 503 {
		t.Fatal("no implicit paid fallback", w.Code)
	}
	if w := call("GET", "/test-one/audio/0", "", false); w.Code != 404 {
		t.Fatal("missing audio", w.Code)
	}
	if w := call("GET", "/test-one/audio/-1", "", false); w.Code != 400 {
		t.Fatal("invalid audio", w.Code)
	}
	h, e = newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	if w := call("GET", "/test-one", "", false); !strings.Contains(w.Body.String(), `"draft":"Müller geht"`) || strings.Contains(w.Body.String(), "Morgen regnet") {
		t.Fatal("restart/redaction", w.Body.String())
	}
	if w := call("PUT", "/test-one", `{"mode":"whole","revision":0}`, true); w.Code != 409 {
		t.Fatal("stale write", w.Code)
	}
	if w := call("POST", "/test-one/check", `{"revision":1}`, true); w.Code != 200 || !strings.Contains(w.Body.String(), "Morgen regnet") {
		t.Fatal("check", w.Code, w.Body.String())
	}
	other, os, _ := cfg.auth.store.create("other", time.Now())
	browser, _ = cfg.auth.store.createBrowser(other, os.UserID, time.Now())
	if w := call("GET", "/test-one", "", false); w.Code != 404 {
		t.Fatal("owner leak", w.Code)
	}
}
func TestDictationPunctuationPosition(t *testing.T) {
	differences := dictationGrade("Heute, gehen wir heim.", "Heute gehen, wir heim.")
	if len(differences) != 1 || differences[0].Kind != "punctuation" {
		t.Fatal("moved punctuation lost", differences)
	}
}

func TestDictationGrade(t *testing.T) {
	g := dictationGrade("Über die Straße, gehen wir heute.", "über die Strasse gehen wir morgen!")
	b, _ := json.Marshal(g)
	s := string(b)
	for _, kind := range []string{"case", "punctuation", "substitution"} {
		if !strings.Contains(s, kind) {
			t.Fatal(kind, s)
		}
	}
	if g := dictationGrade("Ein Café.", "Ein Cafe\u0301."); len(g) != 0 {
		t.Fatal("NFC", g)
	}
}

func TestDictationSegmentation(t *testing.T) {
	text := "Dr. Müller zahlt 3,50 Euro bzw. 2.50 Euro. „Das ist gut!“ Danach fährt er z. B. nach Berlin."
	parts := dictationSentences(text)
	if len(parts) != 3 {
		t.Fatalf("sentences: %#v", parts)
	}
	if !strings.Contains(parts[0], "2.50") || parts[1] != "„Das ist gut!“" {
		t.Fatalf("boundaries: %#v", parts)
	}
	plan := dictationPlan("Heute gehen wir gemeinsam in die schöne Stadt, weil wir dort unsere alten Freunde treffen und zusammen einen langen Spaziergang machen möchten. Danach geht es heim.")
	if plan[0].Kind != "whole" || plan[len(plan)-1].Kind != "final" {
		t.Fatal(plan)
	}
	chunks := 0
	for _, p := range plan {
		if p.Kind == "chunk" {
			chunks++
			if len(strings.Fields(p.Text)) > 14 {
				t.Fatal("unbounded chunk")
			}
		}
	}
	if chunks < 2 {
		t.Fatal("missing writing chunks")
	}
}
