package main

import (
	"encoding/json"
	"math"
	"net/http"
	"os"
	"time"
)

// Policy 1 is opt-in and immutable. Offsets are recovery hints supplied by the
// client, never evidence that audio was heard. This is admission, not DRM.
// Stop receipts are separate from listens: an explicit stop is not an ending.
type dictationStop struct {
	Admission string `json:"admission,omitempty"`
	ID        string `json:"id"`
	Client    string `json:"client"`
	Fence     int    `json:"fence"`
}
type dictationPlayback struct {
	Stops       []dictationStop   `json:"stops,omitempty"`
	Revision    int               `json:"revision"`
	WholeStarts int               `json:"whole_starts"`
	Cursor      int               `json:"cursor"`
	FinalUsed   bool              `json:"final_used"`
	Active      *dictationListen  `json:"active,omitempty"`
	Listens     []dictationListen `json:"listens,omitempty"`
}
type dictationListen struct {
	// Revision before the current ownership began. Nil legacy reservations
	// remain strict-CAS; every resume establishes a new boundary.
	StopBase   *int    `json:"stop_base,omitempty"`
	ID         string  `json:"id"`
	Client     string  `json:"client"`
	Step       int     `json:"step"`
	Fence      int     `json:"fence"`
	Offset     float64 `json:"offset"`
	LeaseUntil int64   `json:"lease_until"`
	Done       bool    `json:"done"`
	Stopped    bool    `json:"stopped,omitempty"`
}

func dictationPolicy(raw json.RawMessage) (int, bool) {
	if len(raw) == 0 {
		return 0, true
	}
	// Exact integer version; reject null, floats, strings and future versions.
	if string(raw) != "1" {
		return 0, false
	}
	return 1, true
}
func (cfg *serverConfig) dictationPlaybackHTTP(w http.ResponseWriter, r *http.Request, owner, id string) {
	if expected := r.Header.Get("X-Dictation-Owner"); expected != "" && expected != owner {
		writeError(w, http.StatusForbidden, "owner changed")
		return
	}
	var in struct {
		Admission string  `json:"admission,omitempty"`
		ID        string  `json:"id"`
		Client    string  `json:"client"`
		Action    string  `json:"action"`
		Step      int     `json:"step"`
		Fence     int     `json:"fence"`
		Offset    float64 `json:"offset"`
	}
	if !learningDecode(w, r, &in) {
		return
	}
	if (in.Admission != "" && (!dictationID.MatchString(in.Admission) || in.Action != "stop")) || !dictationID.MatchString(in.ID) || !dictationID.MatchString(in.Client) || in.Step < 0 || in.Step > 120 || in.Fence < 0 || math.IsNaN(in.Offset) || math.IsInf(in.Offset, 0) || in.Offset < 0 || in.Offset > 7200 {
		// A legacy attempt still gets a policy conflict rather than an upgrade.
		writeError(w, 400, "invalid playback stamp")
		return
	}
	var out dictationPlayback
	err := cfg.dictationWrite(r, owner, func(d *dictationData) error {
		// A request already canceled before admission is not a playback start.
		if err := r.Context().Err(); err != nil {
			return err
		}
		v := dictationFind(d, id)
		if v == nil {
			return errDictationMissing
		}
		if v.PlaybackPolicyVersion != 1 {
			return errDictationConflict
		}
		p := &v.Playback
		now := time.Now().UnixMilli()
		if in.Step >= len(v.Plan) {
			return errDictationConflict
		}
		var prior *dictationListen
		for i := range p.Listens {
			if p.Listens[i].ID == in.ID {
				prior = &p.Listens[i]
				break
			}
		}
		a := p.Active
		if (in.Action == "ended" || in.Action == "cancel") && prior != nil && prior.Done && prior.Step == in.Step && prior.Client == in.Client && prior.Fence == in.Fence {
			out = *p
			return nil
		}
		switch in.Action {
		case "stop":
			for _, receipt := range p.Stops {
				if receipt.ID == in.ID {
					if receipt.Client != in.Client || receipt.Fence != in.Fence || receipt.Admission != in.Admission {
						return errDictationConflict
					}
					out = *p
					return nil
				}
			}
			// Compare the complete ledger, including between-sentence gaps.
			// Do not take over another client's live lease or refund any start.
			// A lost start/progress acknowledgment may leave an older observed
			// fence. Only the named admission's uninterrupted ownership can
			// bridge that gap; never infer ownership from a refreshed revision.
			ownedGap := a != nil && a.StopBase != nil && in.Admission == a.ID && in.Client == a.Client && in.Fence >= *a.StopBase && in.Fence < p.Revision
			if (a != nil && in.Admission != "" && a.ID != in.Admission) || in.Step != 0 || (in.Fence != p.Revision && !ownedGap) || v.Checked || len(p.Stops) >= 256 || (a != nil && a.Client != in.Client && a.LeaseUntil > now) {
				return errDictationConflict
			}
			if a != nil {
				a.Stopped = true // terminal reservation, never a successful ending
				a.Offset = 0
				a.LeaseUntil = 0
			}
			p.Cursor = 1
			p.Revision++
			p.Stops = append(p.Stops, dictationStop{ID: in.ID, Client: in.Client, Fence: in.Fence, Admission: in.Admission})
		case "start":
			for _, receipt := range p.Stops {
				if receipt.Admission == in.ID {
					return errDictationConflict
				}
			}
			if prior != nil {
				if prior.Step != in.Step || prior.Client != in.Client {
					return errDictationConflict
				}
				if prior.Done || prior.Stopped {
					out = *p
					return nil
				}
				if a == nil || a.ID != in.ID || a.Client != in.Client || a.LeaseUntil <= now {
					return errDictationConflict
				}
				out = *p
				return nil
			}
			// Retain bounded idempotency history, including canceled chunks.
			// Four whole starts remain an independent pedagogical policy limit.
			if a != nil || v.Checked || len(p.Listens) >= 256 {
				return errDictationConflict
			}
			kind := v.Plan[in.Step].Kind
			if in.Step != 0 && in.Step != p.Cursor {
				return errDictationConflict
			}
			if kind == "whole" || kind == "final" {
				if p.WholeStarts >= 4 || kind == "final" && p.FinalUsed {
					return errDictationConflict
				}
			}
			// A start never generates assets and cannot admit unavailable audio.
			if _, e := os.Stat(dictationAssetPath(cfg.dictationRoot(owner), id, v.Plan[in.Step].Asset)); e != nil {
				return errDictationMissing
			}
			if kind == "whole" || kind == "final" {
				p.WholeStarts++
			}
			if kind == "final" {
				p.FinalUsed = true
			}
			base := p.Revision
			p.Revision++
			p.Active = &dictationListen{StopBase: &base, ID: in.ID, Client: in.Client, Step: in.Step, Fence: p.Revision, LeaseUntil: now + 15000}
			p.Listens = append(p.Listens, *p.Active)
		case "resume":
			if a == nil || a.ID != in.ID || a.Step != in.Step || a.Fence != in.Fence || v.Checked {
				return errDictationConflict
			}
			if a.LeaseUntil > now && a.Client != in.Client {
				return errDictationConflict
			}
			base := p.Revision
			a.StopBase = &base
			p.Revision++
			a.Client = in.Client
			a.Fence = p.Revision
			a.LeaseUntil = now + 15000
		case "progress", "release", "ended", "cancel":
			if a == nil {
				if (in.Action == "ended" || in.Action == "cancel") && prior != nil && prior.Done && prior.Step == in.Step && prior.Client == in.Client && prior.Fence == in.Fence {
					out = *p
					return nil
				}
				return errDictationConflict
			}
			if a.ID != in.ID || a.Client != in.Client || a.Fence != in.Fence || a.Step != in.Step || a.LeaseUntil <= now {
				return errDictationConflict
			}
			a.Offset = in.Offset
			a.LeaseUntil = now + 15000
			p.Revision++
			if in.Action == "progress" {
				a.Fence = p.Revision
			}
			if in.Action == "release" {
				a.LeaseUntil = 0
			}
			if in.Action == "ended" || in.Action == "cancel" {
				a.Done = true
				if in.Step > 0 && in.Action == "ended" && in.Step == p.Cursor && p.Cursor < len(v.Plan)-1 {
					p.Cursor++
				}
			}
		default:
			return errDictationConflict
		}
		if p.Active != nil {
			for i := range p.Listens {
				if p.Listens[i].ID == p.Active.ID {
					p.Listens[i] = *p.Active
				}
			}
			if p.Active.Done || p.Active.Stopped {
				p.Active = nil
			}
		}
		out = *p
		return nil
	})
	if err != nil {
		dictationError(w, err)
		return
	}
	writeJSON(w, 200, out)
}
