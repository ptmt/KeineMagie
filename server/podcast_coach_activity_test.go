package main

import (
	"path/filepath"
	"testing"
	"time"
)

func TestPodcastStarCoachExplicitDirection(t *testing.T) {
	cfg, h, token, _, j := groupFixture(t)
	starGroup(t, h, token, j.ID, 0, true)
	sources, err := cfg.coachSources(j.Owner)
	if err != nil {
		t.Fatal(err)
	}
	if len(sources) != 1 || sources[0].AnswerLanguage != j.TargetLanguage || sources[0].AnswerLanguage == "" {
		t.Fatalf("starred source lost explicit podcast language pair: %+v", sources)
	}
	turn := coachTurn{Language: j.SourceLanguage, Result: &coachResult{Kind: "cloze", Prompt: "___", Target: "grammar.case", SourceID: sources[0].ID, Quote: sources[0].Text}}
	resolved, err := cfg.coachAssessmentSource(j.Owner, turn)
	if err != nil || resolved.AnswerLanguage != j.TargetLanguage {
		t.Fatalf("assessment direction differs: %+v %v", resolved, err)
	}
}

func TestPodcastCheckedActivityExclusiveAttribution(t *testing.T) {
	cfg := &serverConfig{historyPath: filepath.Join(t.TempDir(), "history.json")}
	at := time.Date(2026, 11, 22, 23, 30, 0, 0, time.UTC)
	a := coachAttempt{ID: "check", Answer: "literal answer", Outcome: "wrong", AssessmentState: "completed", At: at}
	if err := cfg.coachStore("owner").transaction(true, func(d *coachData) error {
		d.Turns = []coachTurn{
			{ID: "podcast", Result: &coachResult{Kind: "cloze", SourceID: "passage-group:episode:0:group"}, PriorAttempts: []coachAttempt{a}, Attempt: &a},
			{ID: "legacy-podcast", Result: &coachResult{Kind: "cloze", SourceID: "passage:episode:1"}, Attempt: &a},
			{ID: "ordinary", Result: &coachResult{Kind: "cloze", SourceID: "translation:one"}, Attempt: &a},
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	loc, err := time.LoadLocation("Europe/Berlin")
	if err != nil {
		t.Fatal(err)
	}
	start := time.Date(2026, 11, 23, 0, 0, 0, 0, loc)
	reopened := &serverConfig{historyPath: cfg.historyPath}
	got := reopened.activityWeek("owner", start, loc)
	if got.Days[0].KnownCount != 3 || got.Days[0].Counts["podcasts"] != 2 || got.Days[0].Counts["coach"] != 1 || got.Sources["podcasts"] != "retained" {
		t.Fatalf("podcast checks not exclusively attributed: %+v", got)
	}
	if got.Days[0].Coverage != "partial" {
		t.Fatal("historical coverage invented")
	}
	if other := reopened.activityWeek("other", start, loc); other.Days[0].KnownCount != 0 {
		t.Fatal("owner leak")
	}
}
