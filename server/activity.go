package main

import (
	"path/filepath"
	"strings"
	"time"
)

// KnownCount is a LOWER BOUND from retained successful translations and checked workflows, never
// a claim of complete historical coverage. No source text or private IDs leave
// this adapter. Unsupported modules are not silently counted as zero.
type activityDay struct {
	Date       string         `json:"date"`
	KnownCount int            `json:"known_count"`
	Coverage   string         `json:"coverage"`
	Counts     map[string]int `json:"counts"`
}
type activitySnapshot struct {
	Version  int               `json:"version"`
	TimeZone string            `json:"time_zone"`
	Days     []activityDay     `json:"days"`
	Sources  map[string]string `json:"sources"`
	Undated  int               `json:"undated"`
}

func (cfg *serverConfig) activityWeek(owner string, start time.Time, loc *time.Location) activitySnapshot {
	result := activitySnapshot{Version: 1, TimeZone: loc.String(), Days: []activityDay{}, Sources: map[string]string{"translator": "unavailable", "podcasts": "unavailable", "coach": "unavailable", "dictation": "unavailable"}}
	index := map[string]int{}
	for i := 0; i < 7; i++ {
		key := start.AddDate(0, 0, i).Format("2006-01-02")
		index[key] = i
		result.Days = append(result.Days, activityDay{Date: key, Coverage: "partial", Counts: map[string]int{"coach": 0, "dictation": 0, "translator": 0, "podcasts": 0}})
	}
	add := func(source string, at time.Time) {
		if at.IsZero() {
			result.Undated++
			return
		}
		if i, ok := index[at.In(loc).Format("2006-01-02")]; ok {
			result.Days[i].KnownCount++
			result.Days[i].Counts[source]++
		}
	}
	// A completed assessment, including wrong/uncertain answers, settles a Check.
	// Skip, generation, discussion, failed/pending checks are not completed checks.
	// Rechecking the same exercise counts once; prior successful evidence survives.
	_ = cfg.coachStore(owner).transaction(false, func(d *coachData) error {
		seen := map[string]bool{}
		for _, turn := range d.Turns {
			if seen[turn.ID] || turn.Result == nil || turn.Result.Kind == "clarification" {
				continue
			}
			attempts := append([]coachAttempt{}, turn.PriorAttempts...)
			if turn.Attempt != nil {
				attempts = append(attempts, *turn.Attempt)
			}
			for _, a := range attempts {
				if strings.TrimSpace(a.Answer) == "" || a.Outcome == "skipped" {
					continue
				}
				if a.AssessmentState != "completed" && a.AssessmentState != "" {
					continue
				}
				if a.Outcome != "correct" && a.Outcome != "wrong" && a.Outcome != "ambiguous" {
					continue
				}
				seen[turn.ID] = true
				// Categories describe source attribution, not the screen used.
				// One settled exercise is never counted in both categories.
				source := "coach"
				if strings.HasPrefix(turn.Result.SourceID, "passage-group:") || strings.HasPrefix(turn.Result.SourceID, "passage:") {
					source = "podcasts"
				}
				add(source, a.At)
				break
			}
		}
		result.Sources["coach"] = "retained"
		result.Sources["podcasts"] = "retained"
		return nil
	})
	// Explicit transcript study is separate from an exercise, never listening.
	if err := cfg.podcastStudyActivity(owner, func(at time.Time) { add("podcasts", at) }); err != nil {
		result.Sources["podcasts"] = "unavailable"
	}
	// Dictation already defines checked as a completed workflow (library stage),
	// NOT a full-text completion or successful optional AI assessment.
	_ = cfg.dictationTransaction(owner, false, func(d *dictationData) error {
		seen := map[string]bool{}
		for _, v := range d.Items {
			if !v.Checked || seen[v.ID] {
				continue
			}
			seen[v.ID] = true
			var at time.Time
			if v.Assessment != nil {
				at, _ = time.Parse(time.RFC3339Nano, v.Assessment.At)
			}
			add("dictation", at) // Never use Created as a check date.
		}
		result.Sources["dictation"] = "retained"
		return nil
	})
	// Only successfully saved account results count. Read the entire owner store:
	// history.list is a presentation window capped at 100, not completion evidence.
	history := &historyStore{path: filepath.Join(filepath.Dir(cfg.historyPath), "users", sessionHash(owner)+".json")}
	_ = history.locked(func() error {
		records, err := history.read()
		if err != nil {
			return err
		}
		seen := map[string]bool{}
		for _, record := range records {
			if record.ID == "" || seen[record.ID] || strings.TrimSpace(record.Translation) == "" {
				continue
			}
			seen[record.ID] = true
			add("translator", record.CreatedAt) // Saved only after successful result; zero dates stay undated.
		}
		result.Sources["translator"] = "retained"
		return nil
	})
	return result
}
