package main

import (
	"encoding/json"
	"fmt"
	"sort"
)

type dictationSegmentAssistance struct {
	SegmentID          string `json:"segment_id"`
	Step               int    `json:"step"`
	Asset              int    `json:"asset"`
	PlannedRepetitions int    `json:"planned_repetitions"`
	PlannedStarted     int    `json:"planned_started"`
	ExtraRequested     int    `json:"extra_requested"`
	Started            int    `json:"started"`
	Completed          int    `json:"completed"`
	Stopped            int    `json:"stopped"`
	Resumes            int    `json:"resumes"`
	Interruptions      int    `json:"interruptions"`
	PlayFailures       int    `json:"play_failures"`
	CompletionUnknown  int    `json:"completion_unknown"`
}
type dictationAssistanceSummary struct {
	Version           int                          `json:"version"`
	Tracking          string                       `json:"tracking"`
	Scope             string                       `json:"scope"`
	Unreported        string                       `json:"unreported"`
	ArchivedUnknown   bool                         `json:"archived_unknown"`
	UnknownAdmissions int                          `json:"unknown_admissions"`
	Segments          []dictationSegmentAssistance `json:"segments"`
}

// Wire adapter intentionally depends on the documented ec47272 JSON contract,
// not new pacing Go types: the independent candidates can be merged without a
// duplicate playback struct. It receives ONLY the owner-locked server record,
// never a client-supplied assistance payload. Pre-v2 stays unknown. Do not deploy
// this pre-v2 branch as a rollback writer against a v2 store.
func dictationAssistanceFromWire(raw []byte) dictationAssistanceSummary {
	out := dictationAssistanceSummary{Version: 1, Tracking: "unknown", Scope: "server_accepted_reports", Unreported: "unknown", Segments: []dictationSegmentAssistance{}}
	var record struct {
		Policy   int                `json:"playback_policy_version"`
		Plan     []dictationSegment `json:"plan"`
		History  json.RawMessage    `json:"pacing_history"`
		Playback struct {
			Listens []struct {
				ID            string `json:"id"`
				Policy        int    `json:"policy_version"`
				Step          int    `json:"step"`
				Asset         *int   `json:"asset"`
				Intent        string `json:"intent"`
				Ended         bool   `json:"ended"`
				Stopped       bool   `json:"stopped"`
				Resumes       int    `json:"resumes"`
				Interruptions int    `json:"interruptions"`
				PlayFailures  int    `json:"play_failures"`
			} `json:"listens"`
		} `json:"playback"`
	}
	if json.Unmarshal(raw, &record) != nil {
		return out
	}
	out.ArchivedUnknown = len(record.History) > 0 && string(record.History) != "null"
	if record.Policy != 2 {
		return out
	}
	out.Tracking = "partial"
	seen := map[string]bool{}
	segments := map[int]*dictationSegmentAssistance{}
	for _, a := range record.Playback.Listens {
		if seen[a.ID] && a.ID != "" {
			continue
		}
		seen[a.ID] = true
		if a.ID == "" || a.Policy != 2 || a.Asset == nil || a.Step < 0 || a.Step >= len(record.Plan) || (a.Intent != "planned" && a.Intent != "extra") || a.Resumes < 0 || a.Interruptions < 0 || a.PlayFailures < 0 {
			out.UnknownAdmissions++
			continue
		}
		if record.Plan[a.Step].Asset != *a.Asset {
			out.UnknownAdmissions++
			continue
		}
		anchor := a.Step
		for anchor > 0 && record.Plan[anchor].Kind == "sentence_repeat" && record.Plan[anchor-1].Asset == *a.Asset {
			anchor--
		}
		s := segments[anchor]
		if s == nil {
			planned := 1
			for i := anchor + 1; i < len(record.Plan) && record.Plan[i].Kind == "sentence_repeat" && record.Plan[i].Asset == *a.Asset; i++ {
				planned++
			}
			s = &dictationSegmentAssistance{SegmentID: fmt.Sprintf("policy2:step%d:asset%d", anchor, *a.Asset), Step: anchor, Asset: *a.Asset, PlannedRepetitions: planned}
			segments[anchor] = s
		}
		s.Started++
		if a.Intent == "extra" {
			s.ExtraRequested++
		} else {
			s.PlannedStarted++
		}
		if a.Ended && !a.Stopped {
			s.Completed++
		} else if a.Stopped {
			s.Stopped++
		} else {
			s.CompletionUnknown++
		}
		s.Resumes += a.Resumes
		s.Interruptions += a.Interruptions
		s.PlayFailures += a.PlayFailures
	}
	keys := []int{}
	for key := range segments {
		keys = append(keys, key)
	}
	sort.Ints(keys)
	for _, key := range keys {
		out.Segments = append(out.Segments, *segments[key])
	}
	return out
}
