package main

import (
	"errors"
	"net/http"
	"path/filepath"
	"time"
)

// An explicit owner declaration, not observed listening or a skill assessment.
// The first accepted study date is immutable; retries cannot create activity.
func (cfg *serverConfig) learningStudyHTTP(w http.ResponseWriter, r *http.Request, owner, id string) {
	if r.Method != "PUT" {
		writeError(w, 405, "method not allowed")
		return
	}
	var in struct{}
	if !learningDecode(w, r, &in) {
		return
	}
	invalid := errors.New("transcript not ready")
	out, err := cfg.passageTransactionChecked(owner, id, func(d *learningData, j podcastJob) error {
		if len(j.Segments) == 0 || j.State != "completed" {
			return invalid
		}
		if d.StudiedEpisodes == nil {
			d.StudiedEpisodes = map[string]time.Time{}
		}
		if _, ok := d.StudiedEpisodes[id]; !ok {
			d.StudiedEpisodes[id] = time.Now().UTC()
			d.PassageRevision++
		}
		return nil
	}, func() error {
		s, e := cfg.auth.store.lookup(bearerSession(r), time.Now())
		if e != nil || s.UserID != owner || r.Context().Err() != nil {
			return errCoachUnauthorized
		}
		return nil
	})
	switch {
	case errors.Is(err, errPodcastNotFound):
		writeError(w, 404, "podcast not found")
	case errors.Is(err, errCoachUnauthorized):
		writeError(w, 401, "authentication failed")
	case errors.Is(err, invalid):
		writeError(w, 409, "transcript not ready")
	case err != nil:
		writeError(w, 503, "could not save study completion")
	default:
		writeJSON(w, 200, out)
	}
}

// Read under the same podcast -> learning lock order as passage writes/deletion.
// Orphaned historical receipts never count, even before cleanup has run.
func (cfg *serverConfig) podcastStudyActivity(owner string, add func(time.Time)) error {
	s := &podcastStore{lock: &historyStore{path: filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json")}}
	return s.lock.locked(func() error {
		pd, err := s.read()
		if err != nil {
			return err
		}
		return cfg.learningStore(owner).transaction(func(d *learningData) error {
			seen := map[string]bool{}
			for _, j := range pd.Jobs {
				if j.Owner != owner || seen[j.ID] {
					continue
				}
				seen[j.ID] = true
				if at, ok := d.StudiedEpisodes[j.ID]; ok {
					add(at)
				}
			}
			return nil
		}, false)
	})
}
