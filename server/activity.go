package main

import (
	"strings"
	"time"
)

// KnownCount is a LOWER BOUND from retained explicit checked workflows, never
// a claim of complete historical coverage. No source text or private IDs leave
// this adapter. Unsupported modules are not silently counted as zero.
type activityDay struct {
	Date       string `json:"date"`
	KnownCount int    `json:"known_count"`
	Coverage   string `json:"coverage"`
}
type activitySnapshot struct {
	Version  int               `json:"version"`
	TimeZone string            `json:"time_zone"`
	Days     []activityDay     `json:"days"`
	Sources  map[string]string `json:"sources"`
	Undated  int               `json:"undated"`
}

func (cfg *serverConfig) activityWeek(owner string, start time.Time, loc *time.Location) activitySnapshot {
	result := activitySnapshot{Version: 1, TimeZone: loc.String(), Days: []activityDay{}, Sources: map[string]string{"translator": "unsupported", "podcasts": "unsupported", "coach": "unavailable", "dictation": "unavailable"}}
	index := map[string]int{}
	for i := 0; i < 7; i++ {
		key := start.AddDate(0, 0, i).Format("2006-01-02")
		index[key] = i
		result.Days = append(result.Days, activityDay{Date: key, Coverage: "partial"})
	}
	add := func(at time.Time) {
		if at.IsZero() {
			result.Undated++
			return
		}
		if i, ok := index[at.In(loc).Format("2006-01-02")]; ok {
			result.Days[i].KnownCount++
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
				add(a.At)
				break
			}
		}
		result.Sources["coach"] = "retained"
		return nil
	})
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
			add(at) // Never use Created as a check date.
		}
		result.Sources["dictation"] = "retained"
		return nil
	})
	return result
}
