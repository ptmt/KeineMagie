package main

import (
	"encoding/json"
	"net/http"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPodcastStarGenerationPriorityAndInvalidation(t *testing.T) {
	for _, mutation := range []string{"kept", "unstar", "delete", "replace-transcript", "replace-language", "assessment-unstar"} {
		t.Run(mutation, func(t *testing.T) {
			f := newAssessmentFixture(t)
			if err := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error { d.Turns = nil; return nil }); err != nil {
				t.Fatal(err)
			}
			store, err := openPodcastStore(filepath.Join(filepath.Dir(f.cfg.historyPath), "podcasts", "jobs.json"))
			if err != nil {
				t.Fatal(err)
			}
			j, err := store.create(f.owner, "https://example.com/synthetic.mp3", "de", time.Now())
			if err != nil {
				t.Fatal(err)
			}
			j, err = store.claim(time.Now())
			if err != nil {
				t.Fatal(err)
			}
			j.State = "completed"
			j.Segments = []podcastSegment{{Text: "Ich muss das Paket abholen.", Translation: "Мне нужно забрать посылку.", Start: 0, End: 4}}
			if err = store.update(j); err != nil {
				t.Fatal(err)
			}
			starGroup(t, f.h, f.token, j.ID, 0, true)
			if f.calls.Load() != 0 {
				t.Fatal("star generated AI")
			}
			f.reply = func(r *http.Request) (string, error) {
				var payload struct {
					Input []struct {
						Content string `json:"content"`
					} `json:"input"`
				}
				if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
					t.Fatal(err)
				}
				var input struct {
					Sources []coachSource `json:"sources"`
				}
				if err := json.Unmarshal([]byte(payload.Input[0].Content), &input); err != nil {
					t.Fatal(err)
				}
				if len(input.Sources) != 1 || !strings.HasPrefix(input.Sources[0].ID, "passage-group:") {
					t.Errorf("starred pool not prioritized: %+v", input.Sources)
				}
				s := input.Sources[0]
				if s.Text != j.Segments[0].Text || s.Language != "de" || s.AnswerLanguage != "ru" {
					t.Errorf("lost grounded pair: %+v", s)
				}
				if mutation == "unstar" {
					starGroup(t, f.h, f.token, j.ID, 0, false)
				}
				if mutation == "replace-transcript" || mutation == "replace-language" {
					if mutation == "replace-transcript" {
						j.Segments[0].Text = "Ein anderer importierter Inhalt."
					} else {
						j.TargetLanguage = "es"
					}
					// Simulate an import replacing persisted source data, not a worker
					// update (completed worker claims intentionally cannot update).
					if err := store.lock.locked(func() error {
						d, err := store.read()
						if err != nil {
							return err
						}
						for i := range d.Jobs {
							if d.Jobs[i].ID == j.ID {
								d.Jobs[i].Segments = j.Segments
								d.Jobs[i].TargetLanguage = j.TargetLanguage
							}
						}
						return store.write(d)
					}); err != nil {
						t.Fatal(err)
					}
				}
				if mutation == "delete" {
					if w := authCall(f.h, "DELETE", "/v1/podcasts/"+j.ID, "", f.token); w.Code != 204 {
						t.Fatal(w.Code)
					}
				}
				raw, _ := json.Marshal(coachResult{Clue: "Collecting the parcel mentioned in the sentence.", ClueKind: "gloss", ClueLanguage: "en", Kind: "context_translation", Message: "Translate the highlighted expression into Russian in this context.", Prompt: s.Text, Quote: s.Text, SourceID: s.ID, Target: "vocabulary.word_choice", TargetText: "abholen", AnswerLanguage: "ru", Answers: []string{"забрать", "получить"}, IncorrectAnswers: []string{}, Explanation: "Collecting the parcel, not fetching a person."})
				return accountTranslationSSE(string(raw), true, "response.completed"), nil
			}
			w := f.call(coachInput{RequestID: "podcast-practice", Action: "practice", Locale: "en"})
			if mutation == "kept" || mutation == "assessment-unstar" {
				if w.Code != 200 {
					t.Fatalf("grounded practice: %d %s", w.Code, w.Body.String())
				}
				if strings.Contains(w.Body.String(), "забрать") {
					t.Fatal("answer leaked")
				}
				if !strings.Contains(w.Body.String(), `"clue":"Collecting the parcel mentioned in the sentence."`) {
					t.Fatal("meaning clue lost in public exercise")
				}
				f.reply = func(r *http.Request) (string, error) {
					if mutation == "assessment-unstar" {
						starGroup(t, f.h, f.token, j.ID, 0, false)
					}
					return accountTranslationSSE(`{"verdict":"correct","corrected_answer":"сходить за посылкой","explanation":"Synthetic contextual alternative, not answer-list grading.","uncertainty_reason":""}`, true, "response.completed"), nil
				}
				checked := f.call(coachInput{RequestID: "podcast-answer", Action: "answer", TurnID: "podcast-practice", Text: "сходить за посылкой", Locale: "en"})
				if checked.Code != 200 {
					t.Fatalf("assessment %d", checked.Code)
				}
				data := f.read(t)
				attempt := coachFind(&data, "podcast-practice").Attempt
				if mutation == "assessment-unstar" {
					if attempt.AssessmentState != "failed" {
						t.Fatal("assessment published from unstarred source")
					}
				} else if attempt.AssessmentState != "completed" || attempt.Outcome != "correct" {
					t.Fatal("contextual alternative rejected")
				}
				if mutation == "kept" {
					calls := f.calls.Load()
					f.call(coachInput{RequestID: "podcast-answer", Action: "answer", TurnID: "podcast-practice", Text: "сходить за посылкой", Locale: "en"})
					if f.calls.Load() != calls {
						t.Fatal("replayed check invoked provider")
					}
					response := authCall(f.h, "GET", "/v1/learning/activity?start="+time.Now().UTC().Format("2006-01-02")+"&time_zone=UTC", "", f.token)
					var activity activitySnapshot
					if err := json.Unmarshal(response.Body.Bytes(), &activity); err != nil {
						t.Fatal(err)
					}
					if response.Code != 200 || activity.Days[0].KnownCount != 1 || activity.Days[0].Counts["podcasts"] != 1 || activity.Days[0].Counts["coach"] != 0 {
						t.Fatalf("real checked flow double counted: %+v", activity)
					}
				}
			} else {
				d := f.read(t)
				for _, v := range d.Turns {
					if v.ID == "podcast-practice" && v.Result != nil {
						t.Fatal("stale unstarred/deleted source published")
					}
				}
			}
		})
	}
}
