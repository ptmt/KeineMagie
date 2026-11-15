package main

import (
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

// Attempts retain their own draft and immutable source. No restart overwrites an attempt.
func (cfg *serverConfig) dictationAttempt(w http.ResponseWriter, r *http.Request, owner, id string) {
	var in struct {
		ID string `json:"id"`
	}
	if !learningDecode(w, r, &in) {
		return
	}
	if !dictationID.MatchString(in.ID) {
		writeError(w, 400, "invalid id")
		return
	}
	var out dictationRecord
	err := cfg.dictationWrite(r, owner, func(d *dictationData) error {
		source := dictationFind(d, id)
		if source == nil {
			return errDictationMissing
		}
		textID := source.TextID
		if textID == "" {
			textID = source.ID
		}
		if d.Deleted[in.ID] {
			return errDictationConflict
		}
		if prior := dictationFind(d, in.ID); prior != nil {
			if prior.TextID != textID {
				return errDictationConflict
			}
			out = *prior
			return nil
		}
		if len(d.Items) >= 30 {
			return errors.New("history limit")
		}
		out = dictationRecord{ID: in.ID, TextID: textID, Title: source.Title, Text: source.Text, Language: source.Language, Created: time.Now().UTC().Format(time.RFC3339), Mode: "whole", Plan: source.Plan, Ready: []int{}}
		d.Items = append(d.Items, out)
		return nil
	})
	if err != nil {
		dictationError(w, err)
		return
	}
	writeJSON(w, 200, dictationPublic(out, false))
}

func (cfg *serverConfig) dictationDelete(w http.ResponseWriter, r *http.Request, owner, id string) {
	var in struct {
		Revision int `json:"revision"`
	}
	if !learningDecode(w, r, &in) {
		return
	}
	err := cfg.dictationWrite(r, owner, func(d *dictationData) error {
		if d.Deleted[id] {
			return nil
		}
		v := dictationFind(d, id)
		if v == nil {
			return errDictationMissing
		}
		if v.Revision != in.Revision {
			return errDictationConflict
		}
		// Keep deletion identifiers so a delayed create cannot resurrect a deleted draft.
		if len(d.Deleted) >= 10000 {
			return errors.New("deletion history limit")
		}
		if d.Deleted == nil {
			d.Deleted = map[string]bool{}
		}
		d.Deleted[id] = true
		delete(d.Mutations, id)
		for i := range d.Items {
			if d.Items[i].ID == id {
				d.Items = append(d.Items[:i], d.Items[i+1:]...)
				break
			}
		}
		return nil
	})
	if err != nil {
		dictationError(w, err)
		return
	}
	// Metadata tombstone commits first; a failed unlink remains inaccessible and retry cleans it.
	if err = os.RemoveAll(filepath.Join(cfg.dictationRoot(owner), id)); err != nil {
		dictationError(w, err)
		return
	}
	writeJSON(w, 200, map[string]bool{"deleted": true})
}
