package main

import (
	"encoding/json"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestCoachSourcesRequireExplicitOwnerPassageMarks(t *testing.T) {
	cfg, h, token, other, j := learningFixture(t)
	session, e := cfg.auth.store.lookup(token, time.Now())
	if e != nil {
		t.Fatal(e)
	}
	sources, e := cfg.coachSources(session.UserID)
	if e != nil || len(sources) != 0 {
		t.Fatal("unsaved passage admitted", sources, e)
	}
	path := "/v1/learning/episodes/" + j.ID + "/passages/0"
	if w := authCall(h, "PUT", path, `{"favorite":true}`, other); w.Code != 404 {
		t.Fatal("foreign passage admitted", w.Code)
	}
	if w := authCall(h, "PUT", path, `{"favorite":true}`, token); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	sources, e = cfg.coachSources(session.UserID)
	if e != nil || len(sources) != 1 || sources[0].Text != j.Segments[0].Text {
		t.Fatal(sources, e)
	}
	if w := authCall(h, "PUT", path, `{"favorite":false}`, token); w.Code != 200 {
		t.Fatal(w.Code)
	}
	sources, e = cfg.coachSources(session.UserID)
	if e != nil || len(sources) != 0 {
		t.Fatal("unmarked source retained", sources, e)
	}
}

func TestCoachConcreteSkillTaxonomy(t *testing.T) {
	base := `{"message":"Practice","kind":"cloze","prompt":"Ich warte ___ den Bus.","target":"verb_government.preposition_case","source_id":"translation:original","quote":"Ich warte auf den Bus.","answers":["auf"],"incorrect_answers":[],"explanation":"warten auf"}`
	sources := []coachSource{{"translation:original", "Ich warte auf den Bus.", "de"}}
	if _, e := decodeCoach(base, sources); e != nil {
		t.Fatal("concrete skill rejected", e)
	}
	if _, e := decodeCoach(strings.Replace(base, "verb_government.preposition_case", "grammar", 1), sources); e == nil {
		t.Fatal("vague dimension accepted as a skill")
	}
}

func TestCoachRejectsMalformedGroundingAndAnswerLeak(t *testing.T) {
	valid := `{"message":"Ergänze den Satz.","kind":"cloze","prompt":"Ich warte ___ den Bus.","target":"verb_government.preposition_case","source_id":"translation:original","quote":"Ich warte auf den Bus.","answers":["auf"],"incorrect_answers":["für"],"explanation":"warten auf + Akkusativ"}`
	sources := []coachSource{{"translation:original", "Ich warte auf den Bus.", "de"}}
	for name, text := range map[string]string{
		"foreign":      strings.Replace(valid, "translation:original", "translation:foreign", 1),
		"forged quote": strings.Replace(valid, `"quote":"Ich warte auf den Bus."`, `"quote":"invented"`, 1),
		"duplicate":    strings.Replace(valid, `"kind":"cloze"`, `"kind":"cloze","kind":"cloze"`, 1),
		"extra":        strings.Replace(valid, `"kind":"cloze"`, `"kind":"cloze","tool":"delete"`, 1),
		"leak":         strings.Replace(valid, "Ergänze den Satz.", "Die Antwort ist auf.", 1),
	} {
		t.Run(name, func(t *testing.T) {
			if _, e := decodeCoach(text, sources); e == nil {
				t.Fatal("accepted invalid result")
			}
		})
	}
}
func TestCoachAttemptEvidenceAndRecovery(t *testing.T) {
	dir := t.TempDir()
	cfg := &serverConfig{authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json")}
	h, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	token, s, e := cfg.auth.store.create("coach-evidence-owner", time.Now())
	if e != nil {
		t.Fatal(e)
	}
	result := &coachResult{Message: "Practice", Kind: "preposition_case", Prompt: "Ich warte ___ den Bus.", Target: "verb_government", SourceID: "translation:one", Quote: "Ich warte auf den Bus.", Answers: []string{"auf"}, IncorrectAnswers: []string{"für"}, Explanation: "warten auf"}
	e = cfg.coachStore(s.UserID).transaction(true, func(d *coachData) error {
		for _, id := range []string{"wrong", "ambiguous", "skip", "assisted", "pending"} {
			state := "completed"
			r := result
			if id == "pending" {
				state = "pending"
				r = nil
			}
			d.Turns = append(d.Turns, coachTurn{ID: id, Text: "Practice", State: state, Result: r, Example: "same-source-quote", Language: "de", At: time.Now()})
		}
		return nil
	})
	if e != nil {
		t.Fatal(e)
	}
	call := func(action, id, text string) map[string]any {
		body, _ := json.Marshal(coachInput{RequestID: action + id + text, Action: action, TurnID: id, Text: text, Locale: "en"})
		r := httptest.NewRequest("POST", "/v1/learning/coach", strings.NewReader(string(body)))
		r.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != 200 {
			t.Fatalf("%s: %d %s", action, w.Code, w.Body.String())
		}
		var v map[string]any
		json.Unmarshal(w.Body.Bytes(), &v)
		return v
	}
	call("answer", "wrong", "für")
	call("answer", "ambiguous", "maybe")
	call("skip", "skip", "")
	call("reveal", "assisted", "")
	value := call("answer", "assisted", "auf")
	obs := value["observations"].([]any)
	if len(obs) != 1 {
		t.Fatal(value)
	}
	o := obs[0].(map[string]any)
	if o["count"] != float64(2) || o["distinct_examples"] != float64(1) || o["correct"] != float64(0) || o["assisted"] != float64(1) {
		t.Fatal(o)
	}
	value = call("review", "wrong", "correct")
	if value["observations"].([]any)[0].(map[string]any)["correct"] != float64(1) {
		t.Fatal(value)
	}
	call("review", "wrong", "excluded")
	value = call("cancel", "pending", "")
	last := value["turns"].([]any)[4].(map[string]any)
	if last["state"] != "canceled" {
		t.Fatal(last)
	}
	value = call("reset", "", "")
	if len(value["observations"].([]any)) != 0 {
		t.Fatal(value)
	}
	if e = cfg.learningStore(s.UserID).transaction(func(d *learningData) error {
		if len(d.Profiles) != 0 {
			t.Fatal("Coach changed CEFR")
		}
		return nil
	}, false); e != nil {
		t.Fatal(e)
	}
}
