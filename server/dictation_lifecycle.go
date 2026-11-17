package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

// Attempts retain their own draft and immutable source. No restart overwrites an attempt.
func (cfg *serverConfig) dictationAttempt(w http.ResponseWriter, r *http.Request, owner, id string) {
	var in struct {
		ID                    string          `json:"id"`
		PlaybackPolicyVersion json.RawMessage `json:"playback_policy_version"`
	}
	if !learningDecode(w, r, &in) {
		return
	}
	if !dictationID.MatchString(in.ID) {
		writeError(w, 400, "invalid id")
		return
	}
	policy, valid := dictationPolicy(in.PlaybackPolicyVersion)
	if !valid {
		writeError(w, 400, "unsupported playback policy")
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
			if prior.TextID != textID || prior.PlaybackPolicyVersion != policy {
				return errDictationConflict
			}
			out = *prior
			return nil
		}
		if len(d.Items) >= 30 {
			return errors.New("history limit")
		}
		out = dictationRecord{PlaybackPolicyVersion: policy, Playback: dictationPlayback{Cursor: 1}, ID: in.ID, TextID: textID, Title: source.Title, Text: source.Text, Language: source.Language, Created: time.Now().UTC().Format(time.RFC3339), Mode: "whole", Plan: source.Plan, Ready: []int{}}
		if policy == 1 {
			seen := map[int]bool{}
			for _, segment := range source.Plan {
				if seen[segment.Asset] {
					continue
				}
				seen[segment.Asset] = true
				from := dictationAssetPath(cfg.dictationRoot(owner), source.ID, segment.Asset)
				to := dictationAssetPath(cfg.dictationRoot(owner), in.ID, segment.Asset)
				info, e := os.Stat(from)
				if errors.Is(e, os.ErrNotExist) {
					continue
				}
				if e != nil {
					return e
				}
				if e = os.MkdirAll(filepath.Dir(to), 0700); e != nil {
					return e
				}
				if e = os.Link(from, to); e != nil {
					if !errors.Is(e, os.ErrExist) {
						return e
					}
					existing, statErr := os.Stat(to)
					if statErr != nil {
						return statErr
					}
					if !os.SameFile(info, existing) {
						return errDictationConflict
					}
				}
				out.Ready = append(out.Ready, segment.Asset)
			}
			if len(out.Ready) > 0 {
				dir, e := os.Open(filepath.Join(cfg.dictationRoot(owner), in.ID))
				if e != nil {
					return e
				}
				e = dir.Sync()
				dir.Close()
				if e != nil {
					return e
				}
			}
		}
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
