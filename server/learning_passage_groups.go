package main

import (
	"errors"
	"net/http"
	"path/filepath"
	"reflect"
	"sort"
)

// Relationships only. Source array indices, quotes and timestamps are never rewritten.
// IDs identify exact membership snapshots, not mutable containers for annotations.
type learningPassageGroup struct {
	ID         string  `json:"id"`
	JobID      string  `json:"job_id"`
	SegmentIDs []int   `json:"segment_ids"`
	Start      float64 `json:"start"`
	End        float64 `json:"end"`
}
type learningPassageGroups struct {
	Version            int                    `json:"version"`
	Revision           uint64                 `json:"revision"`
	JobID              string                 `json:"job_id"`
	Groups             []learningPassageGroup `json:"groups"`
	FavoriteSegmentIDs []int                  `json:"favorite_segment_ids"`
}

func passageGroupsFor(owner string, j podcastJob, marks []learningPassage) []learningPassageGroup {
	valid := make(map[int]bool, len(marks))
	for _, m := range marks {
		if m.JobID == j.ID && m.SegmentID >= 0 && m.SegmentID < len(j.Segments) && j.Segments[m.SegmentID].Text == m.Quote {
			valid[m.SegmentID] = true
		}
	}
	groups := []learningPassageGroup{}
	for i := 0; i < len(j.Segments); {
		if !valid[i] {
			i++
			continue
		}
		g := learningPassageGroup{JobID: j.ID, Start: j.Segments[i].Start}
		for i < len(j.Segments) && valid[i] {
			g.SegmentIDs = append(g.SegmentIDs, i)
			g.End = j.Segments[i].End
			i++
		}
		g.ID = "pg_" + learningDigest(struct {
			Owner, Job string
			Members    []int
		}{owner, j.ID, g.SegmentIDs})
		groups = append(groups, g)
	}
	return groups
}

// Global podcast lock -> owner learning lock is the only nested lock order.
// This fences source deletion/replacement against validation and durable acknowledgement.
func (cfg *serverConfig) passageTransaction(owner, id string, mutate func(*learningData, podcastJob) error) (learningPassageGroups, error) {
	out := learningPassageGroups{Version: 1, JobID: id, Groups: []learningPassageGroup{}, FavoriteSegmentIDs: []int{}}
	s := &podcastStore{lock: &historyStore{path: filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json")}}
	err := s.lock.locked(func() error {
		pd, err := s.read()
		if err != nil {
			return err
		}
		jobs := map[string]podcastJob{}
		for _, j := range pd.Jobs {
			if j.Owner == owner {
				jobs[j.ID] = storedPodcast(j)
			}
		}
		job, ok := jobs[id]
		if !ok && mutate != nil {
			return errPodcastNotFound
		}
		err = cfg.learningStore(owner).transaction(func(d *learningData) error {
			if d.PassageGroupVersion > 1 {
				return errors.New("unsupported passage group version")
			}
			before := learningDigest(append([]learningPassage{}, d.Passages...))
			if mutate != nil {
				if err := mutate(d, job); err != nil {
					return err
				}
			}
			// Recover orphaned relationships after historical/admin deletions, never infer new marks.
			kept := []learningPassage{}
			for _, m := range d.Passages {
				if _, ok := jobs[m.JobID]; ok {
					kept = append(kept, m)
				}
			}
			d.Passages = kept
			byJob := map[string][]learningPassage{}
			for _, m := range kept {
				byJob[m.JobID] = append(byJob[m.JobID], m)
			}
			ids := []string{}
			for jobID := range byJob {
				ids = append(ids, jobID)
			}
			sort.Strings(ids)
			groups := []learningPassageGroup{}
			for _, jobID := range ids {
				groups = append(groups, passageGroupsFor(owner, jobs[jobID], byJob[jobID])...)
			}
			if d.PassageGroupVersion != 1 || before != learningDigest(d.Passages) || !reflect.DeepEqual(groups, append([]learningPassageGroup{}, d.PassageGroups...)) {
				d.PassageRevision++
			}
			d.PassageGroupVersion = 1
			d.PassageGroups = groups
			out.Revision = d.PassageRevision
			for _, g := range groups {
				if g.JobID == id {
					out.Groups = append(out.Groups, g)
					out.FavoriteSegmentIDs = append(out.FavoriteSegmentIDs, g.SegmentIDs...)
				}
			}
			return nil
		}, true)
		if err != nil {
			return err
		}
		if !ok {
			return errPodcastNotFound
		}
		return nil
	})
	return out, err
}

func (cfg *serverConfig) learningPassageGroupsHTTP(w http.ResponseWriter, r *http.Request, owner, id string) {
	if r.Method != "GET" {
		writeError(w, 405, "method not allowed")
		return
	}
	out, err := cfg.passageTransaction(owner, id, nil)
	if errors.Is(err, errPodcastNotFound) {
		writeError(w, 404, "podcast not found")
		return
	}
	if err != nil {
		writeError(w, 503, "passage store unavailable")
		return
	}
	writeJSON(w, 200, out)
}
