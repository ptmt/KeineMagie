package main

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// A passage is one recognizer segment, not necessarily one linguistic sentence.
// Keep explicit passage marks separate from saved words and idioms.
type learningPassage struct {
	JobID     string `json:"job_id"`
	SegmentID int    `json:"segment_id"`
	Quote     string `json:"quote"`
}
type podcastCoverage struct {
	PassageRevision uint64 `json:"passage_revision"`
	Recognized      int    `json:"recognized_segments"`
	Translated      int    `json:"translated_segments"`
	Favorites       int    `json:"favorite_passages"`
	FavoriteIDs     []int  `json:"favorite_segment_ids,omitempty"`
}

func coverageFor(j podcastJob, marks []learningPassage) podcastCoverage {
	c := podcastCoverage{Recognized: len(j.Segments)}
	for _, s := range j.Segments {
		if strings.TrimSpace(s.Translation) != "" {
			c.Translated++
		}
	}
	seen := map[int]bool{}
	for _, m := range marks {
		if m.JobID == j.ID && m.SegmentID >= 0 && m.SegmentID < len(j.Segments) && m.Quote == j.Segments[m.SegmentID].Text && !seen[m.SegmentID] {
			seen[m.SegmentID] = true
			c.FavoriteIDs = append(c.FavoriteIDs, m.SegmentID)
		}
	}
	c.Favorites = len(c.FavoriteIDs)
	return c
}

// One owner-store read for the whole library, never one request/read per row.
func (cfg *serverConfig) podcastCoverage(owner string, jobs []podcastJob) error {
	return cfg.learningStore(owner).transaction(func(d *learningData) error {
		byJob := map[string][]learningPassage{}
		for _, m := range d.Passages {
			byJob[m.JobID] = append(byJob[m.JobID], m)
		}
		for i := range jobs {
			c := coverageFor(jobs[i], byJob[jobs[i].ID])
			c.PassageRevision = d.PassageRevision
			jobs[i].Coverage = &c
		}
		return nil
	}, false)
}
func (cfg *serverConfig) learningPassageHTTP(w http.ResponseWriter, r *http.Request, owner, id, raw string) {
	if r.Method != "PUT" {
		writeError(w, 405, "method not allowed")
		return
	}
	var in struct {
		Favorite *bool `json:"favorite"`
	}
	if !learningDecode(w, r, &in) {
		return
	}
	index, e := strconv.Atoi(raw)
	if e != nil || strconv.Itoa(index) != raw || index < 0 || in.Favorite == nil {
		writeError(w, 400, "invalid passage")
		return
	}
	invalid := errors.New("invalid passage")
	unauthorized := errors.New("session revoked")
	out, e := cfg.passageTransaction(owner, id, func(d *learningData, j podcastJob) error {
		session, err := cfg.auth.store.lookup(bearerSession(r), time.Now())
		if err != nil || session.UserID != owner || r.Context().Err() != nil {
			return unauthorized
		}
		if index >= len(j.Segments) {
			return invalid
		}
		kept := []learningPassage{}
		found := false
		for _, m := range d.Passages {
			if m.JobID == id && m.SegmentID == index {
				if *in.Favorite && !found && m.Quote == j.Segments[index].Text {
					kept = append(kept, m)
					found = true
				}
			} else {
				kept = append(kept, m)
			}
		}
		if *in.Favorite && !found {
			if len(kept) >= 10000 {
				return errors.New("passage limit")
			}
			kept = append(kept, learningPassage{JobID: id, SegmentID: index, Quote: j.Segments[index].Text})
		}
		d.Passages = kept
		return nil
	})
	if errors.Is(e, errPodcastNotFound) {
		writeError(w, 404, "podcast not found")
		return
	}
	if errors.Is(e, invalid) {
		writeError(w, 400, "invalid passage")
		return
	}
	if errors.Is(e, unauthorized) {
		writeError(w, 401, "authentication failed")
		return
	}
	if e != nil {
		writeError(w, 503, "could not save passage")
		return
	}
	writeJSON(w, 200, map[string]any{"job_id": id, "segment_id": index, "favorite": *in.Favorite, "passage_groups": out})
}
