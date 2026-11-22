package main

import (
	"path/filepath"
	"strconv"
	"strings"
)

// Explicit practice prefers the owner's starred transcript spans. Discussion
// keeps its broader context. No generation is triggered by marking or opening.
func coachPracticeSources(sources []coachSource) []coachSource {
	starred := []coachSource{}
	for _, s := range sources {
		if strings.HasPrefix(s.ID, "passage-group:") {
			starred = append(starred, s)
		}
	}
	if len(starred) > 0 {
		return starred
	}
	return sources
}

// Fence publication against unstar, deletion and transcript replacement while
// inference was in flight. Never hold source locks over a provider request.
// Lock order stays podcast -> learning -> auth -> coach, as for passage writes.
func (cfg *serverConfig) coachPublishPodcast(owner string, result coachResult, sources []coachSource, publish func() error) error {
	if !strings.HasPrefix(result.SourceID, "passage-group:") {
		return publish()
	}
	parts := strings.Split(result.SourceID, ":")
	if len(parts) != 4 {
		return errCoachConflict
	}
	var original coachSource
	for _, s := range sources {
		if s.ID == result.SourceID {
			original = s
			break
		}
	}
	if original.ID == "" {
		return errCoachConflict
	}
	store := &podcastStore{lock: &historyStore{path: filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json")}}
	return store.lock.locked(func() error {
		pd, err := store.read()
		if err != nil {
			return err
		}
		var job podcastJob
		for _, j := range pd.Jobs {
			if j.Owner == owner && j.ID == parts[1] {
				job = storedPodcast(j)
				break
			}
		}
		if job.ID == "" {
			return errCoachConflict
		}
		return cfg.learningStore(owner).transaction(func(d *learningData) error {
			for _, g := range passageGroupsFor(owner, job, d.Passages) {
				if g.ID != parts[3] || strconv.Itoa(g.SegmentIDs[0]) != parts[2] {
					continue
				}
				text := []string{}
				for _, index := range g.SegmentIDs {
					text = append(text, job.Segments[index].Text)
				}
				if strings.Join(text, " ") != original.Text || job.SourceLanguage != original.Language || (original.AnswerLanguage != "" && original.AnswerLanguage != job.TargetLanguage) {
					return errCoachConflict
				}
				return publish()
			}
			return errCoachConflict
		}, false)
	})
}
