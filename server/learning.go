package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type learningAssessment struct {
	CEFR       string    `json:"cefr"`
	AssessedAt time.Time `json:"assessed_at"`
}
type learningProgress struct {
	Saved     int `json:"saved"`
	Learning  int `json:"learning"`
	Known     int `json:"known"`
	Favorites int `json:"favorites"`
}
type learningProfile struct {
	Language        string               `json:"language"`
	CEFR            string               `json:"cefr"`
	SelfAssessments []learningAssessment `json:"self_assessments"`
	Progress        learningProgress     `json:"progress"`
}
type learningAction struct {
	Status string    `json:"status"`
	At     time.Time `json:"at"`
}
type learningVocabulary struct {
	ID          string           `json:"id"`
	JobID       string           `json:"job_id"`
	Language    string           `json:"language"`
	SegmentID   int              `json:"segment_id"`
	Quote       string           `json:"quote"`
	Term        string           `json:"term"`
	Kind        string           `json:"kind"`
	Translation string           `json:"translation"`
	Notes       string           `json:"notes"`
	Favorite    bool             `json:"favorite"`
	Status      string           `json:"status"`
	Start       float64          `json:"start"`
	End         float64          `json:"end"`
	CreatedAt   time.Time        `json:"created_at"`
	UpdatedAt   time.Time        `json:"updated_at"`
	History     []learningAction `json:"history"`
}
type learningData struct {
	Passages   []learningPassage          `json:"passages,omitempty"`
	Profiles   map[string]learningProfile `json:"profiles"`
	Vocabulary []learningVocabulary       `json:"vocabulary"`
}
type learningStore struct{ lock *historyStore }

func (cfg *serverConfig) learningStore(owner string) *learningStore {
	return &learningStore{lock: &historyStore{path: filepath.Join(filepath.Dir(cfg.historyPath), "learning", sessionHash(owner)+".json")}}
}
func (s *learningStore) transaction(fn func(*learningData) error, write bool) error {
	return s.lock.locked(func() error {
		d := learningData{Profiles: map[string]learningProfile{}, Vocabulary: []learningVocabulary{}}
		f, e := os.Open(s.lock.path)
		if e == nil {
			defer f.Close()
			b, err := io.ReadAll(io.LimitReader(f, 32<<20+1))
			if err != nil {
				return err
			}
			if len(b) > 32<<20 {
				return errors.New("learning store full")
			}
			if e = json.Unmarshal(b, &d); e != nil {
				return e
			}
			if d.Profiles == nil || d.Vocabulary == nil {
				return errors.New("invalid learning store")
			}
		} else if !errors.Is(e, os.ErrNotExist) {
			return e
		}
		if e = fn(&d); e != nil {
			return e
		}
		if !write {
			return nil
		}
		return learningAtomicJSON(s.lock.path, d)
	})
}
func learningAtomicJSON(path string, value any) error {
	b, e := json.Marshal(value)
	if e != nil {
		return e
	}
	if len(b) > 32<<20 {
		return errors.New("learning storage limit")
	}
	if e = os.MkdirAll(filepath.Dir(path), 0700); e != nil {
		return e
	}
	f, e := os.CreateTemp(filepath.Dir(path), ".learning-*")
	if e != nil {
		return e
	}
	defer os.Remove(f.Name())
	defer f.Close()
	if _, e = f.Write(b); e != nil {
		return e
	}
	if e = f.Sync(); e != nil {
		return e
	}
	if e = f.Close(); e != nil {
		return e
	}
	if e = os.Rename(f.Name(), path); e != nil {
		return e
	}
	dir, e := os.Open(filepath.Dir(path))
	if e != nil {
		return e
	}
	defer dir.Close()
	return dir.Sync()
}
func learningLevel(level string) bool {
	switch level {
	case "unknown", "A1", "A2", "B1", "B2", "C1", "C2":
		return true
	}
	return false
}
func learningLanguage(lang string) bool { return lang == "de" || lang == "ru" }
func learningGetProfile(d *learningData, lang string) learningProfile {
	p, ok := d.Profiles[lang]
	if !ok {
		p = learningProfile{Language: lang, CEFR: "unknown", SelfAssessments: []learningAssessment{}}
	}
	p.Progress = learningProgress{}
	for _, v := range d.Vocabulary {
		if v.Language != lang {
			continue
		}
		switch v.Status {
		case "saved":
			p.Progress.Saved++
		case "learning":
			p.Progress.Learning++
		case "known":
			p.Progress.Known++
		}
		if v.Favorite {
			p.Progress.Favorites++
		}
	}
	return p
}
func learningDecode(w http.ResponseWriter, r *http.Request, v any) bool {
	defer r.Body.Close()
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16384))
	d.DisallowUnknownFields()
	if d.Decode(v) != nil || d.Decode(new(any)) != io.EOF {
		writeError(w, 400, "invalid JSON body")
		return false
	}
	return true
}
func (cfg *serverConfig) handleLearning(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if r.Header.Get("Origin") == "" && cookieValue(r, browserCookie) == "" {
		if s, e := cfg.auth.store.lookup(bearerSession(r), time.Now()); e == nil && s.Kind == "browser" {
			writeError(w, 401, "browser cookie required")
			return
		}
	}
	if r.Header.Get("Origin") != "" || cookieValue(r, browserCookie) != "" {
		token := cookieValue(r, browserCookie)
		session, e := cfg.auth.store.lookup(token, time.Now())
		if e != nil || session.Kind != "browser" {
			writeError(w, 401, "authentication required")
			return
		}
		if r.Method != "GET" && !newBrowserAuth(cfg).mutation(w, r, token) {
			return
		}
		r = r.Clone(r.Context())
		r.Header.Set("Authorization", "Bearer "+token)
	}
	owner, ok := cfg.provider.owner(w, r)
	if !ok {
		return
	}
	parts := strings.Split(strings.Trim(strings.TrimPrefix(r.URL.Path, "/v1/learning/"), "/"), "/")
	store := cfg.learningStore(owner)
	if len(parts) == 4 && parts[0] == "episodes" && parts[2] == "passages" {
		cfg.learningPassageHTTP(w, r, owner, parts[1], parts[3])
		return
	}
	if len(parts) == 3 && parts[0] == "episodes" && parts[2] == "analysis" {
		cfg.learningAnalysisHTTP(w, r, owner, parts[1])
		return
	}
	if len(parts) > 0 && parts[0] == "vocabulary" {
		cfg.learningVocabularyHTTP(w, r, owner, parts)
		return
	}
	if len(parts) == 2 && parts[0] == "profiles" && learningLanguage(parts[1]) {
		if r.Method != "GET" && r.Method != "PUT" {
			writeError(w, 405, "method not allowed")
			return
		}
		var in struct {
			CEFR string `json:"cefr"`
		}
		if r.Method == "PUT" {
			if !learningDecode(w, r, &in) {
				return
			}
			if !learningLevel(in.CEFR) {
				writeError(w, 400, "cefr must be unknown or A1 through C2")
				return
			}
		}
		var profile learningProfile
		e := store.transaction(func(d *learningData) error {
			profile = learningGetProfile(d, parts[1])
			if r.Method == "PUT" {
				profile.CEFR = in.CEFR
				profile.SelfAssessments = append(profile.SelfAssessments, learningAssessment{CEFR: in.CEFR, AssessedAt: time.Now().UTC()})
				d.Profiles[parts[1]] = profile
			}
			return nil
		}, r.Method == "PUT")
		if e != nil {
			writeError(w, 503, "learning store unavailable")
			return
		}
		writeJSON(w, 200, profile)
		return
	}
	writeError(w, 404, "learning resource not found")
}
