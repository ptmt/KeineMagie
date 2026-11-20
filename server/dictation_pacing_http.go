package main

import (
	"encoding/json"
	"net/http"
)

// Preserve old indexes and admission history intact when explicitly upgrading.
// A second upgrade is forbidden; v2 settings may change only before its starts.
type dictationPacingHistory struct {
	Policy   int                `json:"policy"`
	Mode     string             `json:"mode"`
	Plan     []dictationSegment `json:"plan"`
	Playback dictationPlayback  `json:"playback"`
	Step     int                `json:"step"`
	Replays  int                `json:"replays"`
}

func (cfg *serverConfig) dictationPacingHTTP(w http.ResponseWriter, r *http.Request, owner, id string) {
	var in struct {
		Revision         int    `json:"revision"`
		PlaybackRevision int    `json:"playback_revision"`
		MutationID       string `json:"mutation_id"`
		Repeats          int    `json:"repeats"`
		GapSeconds       int    `json:"gap_seconds"`
	}
	if !learningDecode(w, r, &in) {
		return
	}
	if !dictationID.MatchString(in.MutationID) || (in.Repeats != 2 && in.Repeats != 3) || (in.GapSeconds != 3 && in.GapSeconds != 8) {
		writeError(w, 400, "invalid pacing settings")
		return
	}
	encoded, _ := json.Marshal(in)
	digest := sessionHash(string(encoded))
	var out dictationRecord
	err := cfg.dictationWrite(r, owner, func(d *dictationData) error {
		v := dictationFind(d, id)
		if v == nil {
			return errDictationMissing
		}
		if v.PacingMutation == in.MutationID {
			if d.Mutations[id+"/pacing"] != digest {
				return errDictationConflict
			}
			out = *v
			return nil
		}
		if v.Checked || v.Revision != in.Revision || v.Playback.Revision != in.PlaybackRevision || v.Playback.Active != nil {
			return errDictationConflict
		}
		if v.PlaybackPolicyVersion == 2 && len(v.Playback.Listens) > 0 {
			return errDictationConflict
		}
		if v.PlaybackPolicyVersion > 2 {
			return errDictationConflict
		}
		plan := dictationPacingPlan(v.Text, v.Plan, in.Repeats)
		if len(plan) > 2+59*in.Repeats {
			return errDictationConflict
		}
		// Retained legacy asset IDs cannot exceed the audio route's bound.
		for _, segment := range plan {
			if segment.Asset > 120 {
				return errDictationConflict
			}
		}
		if v.PlaybackPolicyVersion != 2 {
			v.PacingHistory = &dictationPacingHistory{Policy: v.PlaybackPolicyVersion, Mode: v.Mode, Plan: v.Plan, Playback: v.Playback, Step: v.Step, Replays: v.Replays}
			v.Playback = dictationPlayback{Revision: v.Playback.Revision + 1, WholeStarts: v.Playback.WholeStarts, FinalUsed: v.Playback.FinalUsed}
		}
		v.Pacing = &dictationPacing{Repeats: in.Repeats, GapSeconds: in.GapSeconds}
		v.PlaybackPolicyVersion = 2
		v.Plan = plan
		v.Step = 0
		v.Revision++
		v.PacingMutation = in.MutationID
		if d.Mutations == nil {
			d.Mutations = map[string]string{}
		}
		d.Mutations[id+"/pacing"] = digest
		out = *v
		return nil
	})
	if err != nil {
		dictationError(w, err)
		return
	}
	writeJSON(w, 200, dictationPublic(out, false))
}
