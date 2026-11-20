package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

type dictationRecord struct {
	Pacing                *dictationPacing        `json:"pacing,omitempty"`
	PacingHistory         *dictationPacingHistory `json:"pacing_history,omitempty"`
	PacingMutation        string                  `json:"pacing_mutation,omitempty"`
	PlaybackPolicyVersion int                     `json:"playback_policy_version,omitempty"`
	Playback              dictationPlayback       `json:"playback"`
	ID                    string                  `json:"id"`
	TextID                string                  `json:"text_id,omitempty"`
	MutationID            string                  `json:"mutation_id,omitempty"`
	Title                 string                  `json:"title"`
	Text                  string                  `json:"text,omitempty"`
	Language              string                  `json:"language"`
	Created               string                  `json:"created"`
	Mode                  string                  `json:"mode"`
	Step                  int                     `json:"step"`
	Replays               int                     `json:"replays"`
	Draft                 string                  `json:"draft"`
	Revision              int                     `json:"revision"`
	Checked               bool                    `json:"checked"`
	Assisted              bool                    `json:"assisted"`
	Plan                  []dictationSegment      `json:"plan"`
	Ready                 []int                   `json:"ready"`
	Differences           []dictationDifference   `json:"differences,omitempty"`
}
type dictationData struct {
	Items       []dictationRecord `json:"items"`
	Deleted     map[string]bool   `json:"deleted,omitempty"`
	Mutations   map[string]string `json:"mutations,omitempty"`
	Day         string            `json:"day"`
	Generations int               `json:"generations"`
}

var dictationID = regexp.MustCompile(`^[A-Za-z0-9_-]{1,80}$`)
var errDictationMissing = errors.New("dictation not found")
var errDictationConflict = errors.New("changed elsewhere; reload before saving")

func (cfg *serverConfig) dictationRoot(owner string) string {
	return filepath.Join(filepath.Dir(cfg.historyPath), "dictations", sessionHash(owner))
}
func (cfg *serverConfig) dictationTransaction(owner string, write bool, fn func(*dictationData) error) error {
	lock := &historyStore{path: filepath.Join(cfg.dictationRoot(owner), "history.json")}
	return lock.locked(func() error {
		d := dictationData{Items: []dictationRecord{}}
		b, e := os.ReadFile(lock.path)
		if e == nil {
			if len(b) > 8<<20 {
				return errors.New("history limit")
			}
			if e = json.Unmarshal(b, &d); e != nil {
				return e
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
		encoded, err := json.Marshal(d)
		if err != nil {
			return err
		}
		if len(encoded) > 8<<20 {
			return errors.New("history limit")
		}
		return learningAtomicJSON(lock.path, d)
	})
}

// Serialize mutations against logout. No synthesis runs while the identity/store locks are held.
func (cfg *serverConfig) dictationWrite(r *http.Request, owner string, fn func(*dictationData) error) error {
	return cfg.auth.store.lock.locked(func() error {
		d, e := cfg.auth.store.read()
		if e != nil {
			return e
		}
		s := d.Sessions[sessionHash(bearerSession(r))]
		if s.UserID != owner || !cfg.auth.now().Before(s.Expires) {
			return errCoachUnauthorized
		}
		return cfg.dictationTransaction(owner, true, fn)
	})
}
func dictationFind(d *dictationData, id string) *dictationRecord {
	for i := range d.Items {
		if d.Items[i].ID == id {
			return &d.Items[i]
		}
	}
	return nil
}
func dictationPublic(v dictationRecord, list bool) dictationRecord {
	v.PacingHistory = nil // Archived source/ledger must never leak the answer.
	v.Plan = append([]dictationSegment{}, v.Plan...)
	if !v.Checked && !v.Assisted || list {
		v.Text = ""
		for i := range v.Plan {
			v.Plan[i].Text = ""
		}
	}
	if list {
		v.Draft = ""
		v.Differences = nil
		v.Plan = []dictationSegment{}
	}
	return v
}
func dictationError(w http.ResponseWriter, e error) {
	code := 503
	if errors.Is(e, errDictationMissing) {
		code = 404
	}
	if errors.Is(e, errDictationConflict) {
		code = 409
	}
	if errors.Is(e, errCoachUnauthorized) {
		code = 401
	}
	if errors.Is(e, errDictationBudget) {
		code = 429
	}
	msg := "Dictation unavailable. Retry explicitly."
	if errors.Is(e, errDictationSpeech) {
		msg = "Audio generation failed or was interrupted. Retrying may incur another OpenAI charge."
	}
	if code == 429 {
		msg = "Speech application limit reached. Cached playback is still available."
	}
	if code == 404 || code == 409 {
		msg = e.Error()
	}
	if code == 429 {
		writeJSON(w, code, map[string]any{"error": msg, "code": "speech_budget_exhausted"})
		return
	}
	writeError(w, code, msg)
}
func (cfg *serverConfig) dictationHTTP(w http.ResponseWriter, r *http.Request, owner string) {
	suffix := strings.TrimPrefix(r.URL.Path, "/v1/learning/dictations")
	parts := strings.Split(strings.Trim(suffix, "/"), "/")
	id := parts[0]
	if id != "" && !dictationID.MatchString(id) {
		writeError(w, 400, "invalid id")
		return
	}
	if len(parts) > 1 && parts[1] == "audio" {
		cfg.dictationAudio(w, r, owner, id, parts[2:])
		return
	}
	if id == "" {
		if r.Method == "GET" {
			items := []dictationLibraryItem{}
			e := cfg.dictationTransaction(owner, false, func(d *dictationData) error {
				for i := len(d.Items) - 1; i >= 0; i-- {
					items = append(items, cfg.dictationLibraryItem(owner, d.Items[i]))
				}
				return nil
			})
			if e != nil {
				dictationError(w, e)
				return
			}
			writeJSON(w, 200, map[string]any{"items": items, "speech_spend": cfg.dictationSpeechSpend(owner), "tts_available": dictationTTSAvailable(), "languages": []string{"de"}})
			return
		}
		if r.Method != "POST" {
			writeError(w, 405, "method not allowed")
			return
		}
		var in struct {
			ID                    string          `json:"id"`
			Title                 string          `json:"title"`
			Text                  string          `json:"text"`
			Language              string          `json:"language"`
			PlaybackPolicyVersion json.RawMessage `json:"playback_policy_version"`
		}
		if !learningDecode(w, r, &in) {
			return
		}
		if !dictationID.MatchString(in.ID) || strings.TrimSpace(in.Title) == "" || runeCount(in.Title) > 80 || strings.TrimSpace(in.Text) == "" || runeCount(in.Text) > 1800 || len(dictationWords.FindAllString(in.Text, -1)) > 300 || in.Language != "de" {
			writeError(w, 400, "Use German text up to 1800 characters / 300 words and a title up to 80 characters.")
			return
		}
		policy, valid := dictationPolicy(in.PlaybackPolicyVersion)
		if !valid {
			writeError(w, 400, "unsupported playback policy")
			return
		}
		plan := dictationPlan(in.Text)
		mode, cursor := "whole", 1
		var pacing *dictationPacing
		if policy == 2 {
			pacing = &dictationPacing{Repeats: 2, GapSeconds: 3}
			plan = dictationPacingPlan(in.Text, nil, pacing.Repeats)
			mode, cursor = "sentences", 0
		}
		if len(plan) > 120 {
			writeError(w, 400, "Too many sentences; use a shorter text.")
			return
		}
		var out dictationRecord
		e := cfg.dictationWrite(r, owner, func(d *dictationData) error {
			if d.Deleted[in.ID] {
				return errDictationConflict
			}
			if v := dictationFind(d, in.ID); v != nil {
				if v.Text != in.Text || v.Title != in.Title || v.Language != in.Language || v.PlaybackPolicyVersion != policy {
					return errDictationConflict
				}
				out = *v
				return nil
			}
			if len(d.Items) >= 30 {
				return errors.New("history limit")
			}
			out = dictationRecord{Pacing: pacing, PlaybackPolicyVersion: policy, Playback: dictationPlayback{Cursor: cursor}, ID: in.ID, TextID: in.ID, Title: in.Title, Text: in.Text, Language: in.Language, Created: time.Now().UTC().Format(time.RFC3339), Mode: mode, Plan: plan, Ready: []int{}}
			d.Items = append(d.Items, out)
			return nil
		})
		if e != nil {
			dictationError(w, e)
			return
		}
		writeJSON(w, 200, dictationPublic(out, false))
		return
	}
	action := ""
	if len(parts) > 1 {
		action = parts[1]
	}
	if len(parts) > 2 {
		writeError(w, 404, "not found")
		return
	}
	if action == "playback" && r.Method == "POST" {
		cfg.dictationPlaybackHTTP(w, r, owner, id)
		return
	}
	if action == "pacing" && r.Method == "POST" {
		cfg.dictationPacingHTTP(w, r, owner, id)
		return
	}
	if action == "attempts" && r.Method == "POST" {
		cfg.dictationAttempt(w, r, owner, id)
		return
	}
	if action == "" && r.Method == "DELETE" {
		cfg.dictationDelete(w, r, owner, id)
		return
	}
	var progress struct {
		Mode       string `json:"mode"`
		Step       int    `json:"step"`
		Replays    int    `json:"replays"`
		Draft      string `json:"draft"`
		Revision   int    `json:"revision"`
		MutationID string `json:"mutation_id,omitempty"`
	}
	var actionRevision *int
	write := false
	switch {
	case r.Method == "GET" && action == "":
	case r.Method == "PUT" && action == "":
		write = true
		if !learningDecode(w, r, &progress) {
			return
		}
		if progress.MutationID != "" && !dictationID.MatchString(progress.MutationID) {
			writeError(w, 400, "invalid mutation id")
			return
		}
		if (progress.Mode != "whole" && progress.Mode != "sentences") || progress.Step < 0 || progress.Replays < 0 || progress.Replays > 100000 || runeCount(progress.Draft) > 2400 || len(dictationWords.FindAllString(progress.Draft, -1)) > 400 {
			writeError(w, 400, "invalid practice progress")
			return
		}
	case r.Method == "POST" && (action == "check" || action == "reveal"):
		write = true
		var in struct {
			Revision *int `json:"revision"`
		}
		if !learningDecode(w, r, &in) {
			return
		}
		actionRevision = in.Revision
		if actionRevision == nil {
			writeError(w, 400, "revision required")
			return
		}
	default:
		writeError(w, 405, "method not allowed")
		return
	}
	var out dictationRecord
	fn := func(d *dictationData) error {
		v := dictationFind(d, id)
		if v == nil {
			return errDictationMissing
		}
		if r.Method == "PUT" {
			encoded, _ := json.Marshal(progress)
			digest := sessionHash(string(encoded))
			if progress.MutationID != "" && v.MutationID == progress.MutationID {
				if d.Mutations[id] != digest {
					return errDictationConflict
				}
				out = *v
				return nil
			}
			if v.Revision != progress.Revision || v.Checked {
				return errDictationConflict
			}
			if progress.Step >= len(v.Plan) {
				return errDictationConflict
			}
			v.Mode = progress.Mode
			v.Step = progress.Step
			v.Replays = progress.Replays
			v.Draft = progress.Draft
			v.MutationID = progress.MutationID
			if d.Mutations == nil {
				d.Mutations = map[string]string{}
			}
			d.Mutations[id] = digest
			v.Revision++
		}
		if (action == "check" && !v.Checked || action == "reveal" && !v.Assisted) && (actionRevision == nil || *actionRevision != v.Revision) {
			return errDictationConflict
		}
		if action == "check" && !v.Checked {
			if strings.TrimSpace(v.Draft) == "" {
				return errDictationConflict
			}
			v.Checked = true
			v.Differences = dictationGrade(v.Text, v.Draft)
			v.Revision++
		}
		if action == "reveal" && !v.Assisted {
			v.Assisted = true
			v.Revision++
		}
		out = *v
		return nil
	}
	var e error
	if write {
		e = cfg.dictationWrite(r, owner, fn)
	} else {
		e = cfg.dictationTransaction(owner, false, fn)
	}
	if e != nil {
		dictationError(w, e)
		return
	}
	writeJSON(w, 200, dictationPublic(out, false))
}
func dictationAssetPath(root, id string, index int) string {
	return filepath.Join(root, id, strconv.Itoa(index)+".wav")
}
