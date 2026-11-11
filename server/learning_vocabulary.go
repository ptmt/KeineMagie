package main

import (
	"errors"
	"net/http"
	"path/filepath"
	"strings"
	"time"
)

func (cfg *serverConfig) learningJob(owner, id string) (podcastJob, error) {
	s, e := openPodcastStore(filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json"))
	if e != nil {
		return podcastJob{}, e
	}
	jobs, e := s.list(owner)
	if e != nil {
		return podcastJob{}, e
	}
	for _, j := range jobs {
		if j.ID == id {
			return j, nil
		}
	}
	return podcastJob{}, errPodcastNotFound
}
func learningStatus(s string) bool { return s == "saved" || s == "learning" || s == "known" }
func (cfg *serverConfig) learningVocabularyHTTP(w http.ResponseWriter, r *http.Request, owner string, parts []string) {
	store := cfg.learningStore(owner)
	if len(parts) == 1 && r.Method == "GET" {
		items := []learningVocabulary{}
		e := store.transaction(func(d *learningData) error {
			for _, v := range d.Vocabulary {
				if lang := r.URL.Query().Get("language"); lang != "" && lang != v.Language {
					continue
				}
				if id := r.URL.Query().Get("job_id"); id != "" && id != v.JobID {
					continue
				}
				items = append(items, v)
			}
			return nil
		}, false)
		if e != nil {
			writeError(w, 503, "learning store unavailable")
			return
		}
		writeJSON(w, 200, map[string]any{"items": items})
		return
	}
	if len(parts) == 1 && r.Method == "POST" {
		var in struct {
			JobID       string `json:"job_id"`
			SegmentID   *int   `json:"segment_id"`
			Quote       string `json:"quote"`
			Term        string `json:"term"`
			Kind        string `json:"kind"`
			Translation string `json:"translation"`
			Notes       string `json:"notes"`
			Favorite    bool   `json:"favorite"`
			Status      string `json:"status"`
		}
		if !learningDecode(w, r, &in) {
			return
		}
		j, e := cfg.learningJob(owner, in.JobID)
		if errors.Is(e, errPodcastNotFound) {
			writeError(w, 404, "podcast not found")
			return
		}
		if e != nil {
			writeError(w, 503, "podcast store unavailable")
			return
		}
		if in.Status == "" {
			in.Status = "saved"
		}
		if in.SegmentID == nil || *in.SegmentID < 0 || *in.SegmentID >= len(j.Segments) || strings.TrimSpace(in.Quote) == "" || runeCount(in.Quote) > 4000 || strings.TrimSpace(in.Term) == "" || runeCount(in.Term) > 200 || !strings.Contains(strings.ToLower(in.Quote), strings.ToLower(in.Term)) || (in.Kind != "word" && in.Kind != "idiom") || !learningStatus(in.Status) || runeCount(in.Translation) > 4000 || runeCount(in.Notes) > 4000 {
			writeError(w, 400, "invalid vocabulary source or fields")
			return
		}
		source := j.Segments[*in.SegmentID]
		if !strings.Contains(source.Text, in.Quote) {
			writeError(w, 400, "quote must occur exactly in source segment")
			return
		}
		now := time.Now().UTC()
		v := learningVocabulary{ID: randomAuthToken(), JobID: j.ID, Language: j.SourceLanguage, SegmentID: *in.SegmentID, Quote: in.Quote, Term: in.Term, Kind: in.Kind, Translation: in.Translation, Notes: in.Notes, Favorite: in.Favorite, Status: in.Status, Start: source.Start, End: source.End, CreatedAt: now, UpdatedAt: now, History: []learningAction{{Status: in.Status, At: now}}}
		e = store.transaction(func(d *learningData) error {
			if len(d.Vocabulary) >= 10000 {
				return errors.New("vocabulary limit")
			}
			d.Vocabulary = append(d.Vocabulary, v)
			return nil
		}, true)
		if e != nil {
			writeError(w, 503, "could not save vocabulary")
			return
		}
		writeJSON(w, 201, v)
		return
	}
	if len(parts) == 2 && (r.Method == "PATCH" || r.Method == "DELETE") {
		var in struct {
			Translation *string `json:"translation"`
			Notes       *string `json:"notes"`
			Favorite    *bool   `json:"favorite"`
			Status      *string `json:"status"`
		}
		if r.Method == "PATCH" {
			if !learningDecode(w, r, &in) {
				return
			}
			if (in.Translation == nil && in.Notes == nil && in.Favorite == nil && in.Status == nil) || (in.Translation != nil && runeCount(*in.Translation) > 4000) || (in.Notes != nil && runeCount(*in.Notes) > 4000) || (in.Status != nil && !learningStatus(*in.Status)) {
				writeError(w, 400, "invalid vocabulary patch")
				return
			}
		}
		var result learningVocabulary
		e := store.transaction(func(d *learningData) error {
			for i := range d.Vocabulary {
				v := &d.Vocabulary[i]
				if v.ID != parts[1] {
					continue
				}
				if r.Method == "DELETE" {
					d.Vocabulary = append(d.Vocabulary[:i], d.Vocabulary[i+1:]...)
					return nil
				}
				now := time.Now().UTC()
				if in.Status != nil && *in.Status != v.Status {
					v.Status = *in.Status
					v.History = append(v.History, learningAction{Status: v.Status, At: now})
				}
				if in.Favorite != nil {
					v.Favorite = *in.Favorite
				}
				if in.Notes != nil {
					v.Notes = *in.Notes
				}
				if in.Translation != nil {
					v.Translation = *in.Translation
				}
				v.UpdatedAt = now
				result = *v
				return nil
			}
			return errHistoryNotFound
		}, true)
		if errors.Is(e, errHistoryNotFound) {
			writeError(w, 404, "vocabulary not found")
			return
		}
		if e != nil {
			writeError(w, 503, "could not save vocabulary")
			return
		}
		if r.Method == "DELETE" {
			w.WriteHeader(204)
			return
		}
		writeJSON(w, 200, result)
		return
	}
	writeError(w, 405, "method not allowed")
}
