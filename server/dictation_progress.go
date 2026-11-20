package main

// Transparent retained evidence, not a language-level estimate. Reading this
// snapshot never invokes a provider. Rechecking a receipt does not add an entry.
type dictationProgressEntry struct {
	AttemptID      string `json:"attempt_id"`
	At             string `json:"at"`
	Complete       bool   `json:"complete"`
	Assisted       bool   `json:"assisted"`
	ExactWords     int    `json:"exact_words"`
	AttemptedWords int    `json:"attempted_words"`
	SourceWords    int    `json:"source_words"`
	Additions      int    `json:"additions"`
	Omissions      int    `json:"omissions"`
	Substitutions  int    `json:"substitutions"`
	ReplayTracking string `json:"replay_tracking"`
}
type dictationProgressSummary struct {
	Attempts        int                      `json:"attempts"`
	DistinctSources int                      `json:"distinct_sources"`
	PartialAttempts int                      `json:"partial_attempts"`
	LegacyUnknown   int                      `json:"legacy_unknown"`
	ExactWords      int                      `json:"exact_words"`
	AttemptedWords  int                      `json:"attempted_words"`
	SourceWords     int                      `json:"source_words"`
	ReplayUnknown   int                      `json:"replay_unknown"`
	Entries         []dictationProgressEntry `json:"entries"`
}

func dictationProgress(records []dictationRecord) dictationProgressSummary {
	p := dictationProgressSummary{Entries: []dictationProgressEntry{}}
	sources := map[string]bool{}
	seen := map[string]bool{}
	for _, v := range records {
		if !v.Checked || seen[v.ID] {
			continue
		}
		seen[v.ID] = true
		a := v.Assessment
		if a == nil {
			p.LegacyUnknown++
			continue
		}
		p.Attempts++
		sources[sessionHash(a.Source)] = true
		if a.Alignment.UnattemptedWords > 0 {
			p.PartialAttempts++
		}
		if a.ReplayTracking != "known" {
			p.ReplayUnknown++
		}
		p.ExactWords += a.Alignment.ExactWords
		p.AttemptedWords += a.Alignment.AttemptedWords
		p.SourceWords += a.Alignment.SourceWords
		p.Entries = append(p.Entries, dictationProgressEntry{v.ID, a.At, a.Alignment.Complete, a.Assisted, a.Alignment.ExactWords, a.Alignment.AttemptedWords, a.Alignment.SourceWords, a.Alignment.Additions, a.Alignment.Omissions, a.Alignment.Substitutions, a.ReplayTracking})
	}
	p.DistinctSources = len(sources)
	return p
}
