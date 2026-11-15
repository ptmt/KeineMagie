package main

import (
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"time"
)

// Counts describe retained activity, not mastery. Unavailable is not zero.
type coachCoverage struct {
	Status          string         `json:"status"`
	Count           int            `json:"count"`
	Recent          int            `json:"last_30_days"`
	RecencyCoverage string         `json:"recency_coverage"`
	Statuses        map[string]int `json:"self_reported_statuses,omitempty"`
	Assisted        int            `json:"assisted,omitempty"`
	Differences     int            `json:"recorded_differences,omitempty"`
}

func (c coachCoverage) MarshalJSON() ([]byte, error) {
	value := map[string]any{"status": c.Status, "recency_coverage": c.RecencyCoverage}
	if c.Status == "available" {
		value["count"] = c.Count
		if c.RecencyCoverage != "" && c.RecencyCoverage != "unavailable" && c.RecencyCoverage != "unavailable: saved passages have no timestamps" {
			value["last_30_days"] = c.Recent
		}
		value["assisted"] = c.Assisted
		value["recorded_differences"] = c.Differences
		if c.Statuses != nil {
			value["self_reported_statuses"] = c.Statuses
		}
	}
	return json.Marshal(value)
}

type coachProgressContext struct {
	AsOf         time.Time          `json:"as_of"`
	Period       string             `json:"period"`
	Translations coachCoverage      `json:"translations"`
	Coach        coachCoverage      `json:"coach_answers"`
	Vocabulary   coachCoverage      `json:"vocabulary_statuses"`
	Passages     coachCoverage      `json:"saved_podcast_passages"`
	Dictation    coachCoverage      `json:"dictation_checks"`
	Observations []coachObservation `json:"observations"`
}

func (cfg *serverConfig) coachProgress(owner string, now time.Time) coachProgressContext {
	p := coachProgressContext{AsOf: now, Period: "Retained records; last_30_days uses saved timestamps. Translation coverage: latest 100. Dictation: latest saved check per item, not all historical attempts. Vocabulary statuses are self-reported, not demonstrated mastery.", Observations: []coachObservation{}}
	unavailable := coachCoverage{Status: "unavailable", RecencyCoverage: "unavailable"}
	p.Translations = unavailable
	p.Coach = unavailable
	p.Vocabulary = unavailable
	p.Passages = unavailable
	p.Dictation = unavailable
	add := func(c *coachCoverage, at time.Time) {
		c.Count++
		if !at.IsZero() && !at.Before(now.AddDate(0, 0, -30)) && !at.After(now) {
			c.Recent++
		}
	}
	h, e := openHistory(filepath.Join(filepath.Dir(cfg.historyPath), "users", sessionHash(owner)+".json"))
	if e == nil {
		if items, e := h.list(); e == nil {
			p.Translations.Status = "available"
			p.Translations.RecencyCoverage = "saved creation timestamps"
			for _, v := range items {
				add(&p.Translations, v.CreatedAt)
			}
		}
	}
	_ = cfg.coachStore(owner).transaction(false, func(d *coachData) error {
		p.Coach.Status = "available"
		p.Coach.RecencyCoverage = "saved answer timestamps; since observation reset"
		for _, t := range d.Turns {
			a := t.Attempt
			if a != nil && !a.Excluded && (a.AssessmentState == "" || a.AssessmentState == "completed") && a.Outcome != "skipped" && (d.ResetAt == nil || a.At.After(*d.ResetAt)) {
				add(&p.Coach, a.At)
				if a.Assisted {
					p.Coach.Assisted++
				}
			}
		}
		p.Observations = coachView(d)["observations"].([]coachObservation)
		return nil
	})
	_ = cfg.learningStore(owner).transaction(func(d *learningData) error {
		p.Vocabulary.Status = "available"
		p.Vocabulary.RecencyCoverage = "latest update per item, not learning attempts"
		p.Vocabulary.Statuses = map[string]int{"saved": 0, "learning": 0, "known": 0}
		p.Passages.Status = "available"
		p.Passages.RecencyCoverage = "unavailable: saved passages have no timestamps"
		for _, v := range d.Vocabulary {
			add(&p.Vocabulary, v.UpdatedAt)
			if _, ok := p.Vocabulary.Statuses[v.Status]; ok {
				p.Vocabulary.Statuses[v.Status]++
			}
		}
		for range d.Passages {
			add(&p.Passages, time.Time{})
		}
		return nil
	}, false)
	// Read-only compatibility adapter for the separate, not-yet-merged Dictation work.
	// Never import its dirty files or access text, drafts, audio, private IDs or keys.
	path := filepath.Join(filepath.Dir(cfg.historyPath), "dictations", sessionHash(owner), "history.json")
	lock := &historyStore{path: path}
	_ = lock.locked(func() error {
		f, e := os.Open(path)
		if e != nil {
			return e
		}
		defer f.Close()
		var data struct {
			Items []struct {
				Checked     bool   `json:"checked"`
				Created     string `json:"created"`
				Assisted    bool   `json:"assisted"`
				Differences []struct {
					Kind string `json:"kind"`
				} `json:"differences"`
			} `json:"items"`
		}
		dec := json.NewDecoder(io.LimitReader(f, (8<<20)+1))
		if e = dec.Decode(&data); e != nil {
			return e
		}
		if dec.Decode(new(any)) != io.EOF || data.Items == nil {
			return io.ErrUnexpectedEOF
		}
		c := coachCoverage{Status: "available", RecencyCoverage: "item creation date only; check date unavailable"}
		for _, v := range data.Items {
			if v.Checked {
				at, _ := time.Parse(time.RFC3339, v.Created)
				add(&c, at)
				if v.Assisted {
					c.Assisted++
				}
				c.Differences += len(v.Differences)
			}
		}
		p.Dictation = c
		return nil
	})
	return p
}
