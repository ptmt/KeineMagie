package main

import (
	"encoding/binary"
	"io"
	"os"
	"strings"

	"golang.org/x/text/unicode/norm"
)

// Additive list-only metadata: never return the source or a learner's draft.
// Older clients ignore these fields; older web clients can omit their display.
type dictationLibraryItem struct {
	dictationRecord
	LifecycleStage       string  `json:"lifecycle_stage,omitempty"`
	WordCount            int     `json:"word_count"`
	AudioDurationSeconds float64 `json:"audio_duration_seconds,omitempty"`
}

func (cfg *serverConfig) dictationLibraryItem(owner string, v dictationRecord) dictationLibraryItem {
	item := dictationLibraryItem{dictationRecord: dictationPublic(v, true), WordCount: len(dictationWords.FindAllString(norm.NFC.String(v.Text), -1)), LifecycleStage: cfg.dictationLibraryStage(owner, v)}
	for _, segment := range v.Plan {
		if segment.Kind != "whole" {
			continue
		}
		for _, ready := range v.Ready {
			if ready == segment.Asset {
				item.AudioDurationSeconds = dictationCachedDuration(dictationAssetPath(cfg.dictationRoot(owner), v.ID, ready))
				return item
			}
		}
	}
	return item
}

// A milestone is not proof that all preceding milestones occurred. In particular,
// typing/checking needs no audio. Never infer work from opening/revision/cursor.
func (cfg *serverConfig) dictationLibraryStage(owner string, v dictationRecord) string {
	if v.Checked {
		return "completed"
	}
	started := strings.TrimSpace(v.Draft) != ""
	if v.PlaybackPolicyVersion == 1 || v.PlaybackPolicyVersion == 2 {
		// Admission is durable even when playback is later interrupted/canceled;
		// it is a start, not evidence of hearing or completing a recording.
		started = started || v.Playback.WholeStarts > 0 || len(v.Playback.Listens) > 0
	} else {
		started = started || v.Replays > 0
	}
	if started {
		return "started"
	}
	// Mirror the explicit preparation contract: policy whole = asset 0;
	// policy passages = remaining sequence (including final whole); legacy =
	// current step only. Use the stored plan, not assumptions about asset IDs.
	if len(v.Plan) == 0 {
		return "added"
	}
	segments := v.Plan[:1]
	if v.Mode == "sentences" {
		step := v.Step
		if v.PlaybackPolicyVersion == 1 || v.PlaybackPolicyVersion == 2 {
			step = v.Playback.Cursor
		}
		if step < 0 || step >= len(v.Plan) {
			return "added"
		}
		segments = v.Plan[step : step+1]
		if v.PlaybackPolicyVersion == 1 || v.PlaybackPolicyVersion == 2 {
			segments = v.Plan[step:]
		}
	} else if v.Mode != "whole" {
		return "added"
	}
	ready := make(map[int]bool, len(v.Ready))
	for _, asset := range v.Ready {
		ready[asset] = true
	}
	seen := make(map[int]bool)
	for _, segment := range segments {
		if seen[segment.Asset] {
			continue
		}
		seen[segment.Asset] = true
		if !ready[segment.Asset] {
			return "added"
		}
		info, err := os.Stat(dictationAssetPath(cfg.dictationRoot(owner), v.ID, segment.Asset))
		if err != nil || !info.Mode().IsRegular() || info.Size() == 0 {
			return "added"
		}
	}
	return "ready"
}

// Our cached PCM WAVs have a canonical 44-byte header (dictation_openai.go).
// Read only that header plus stat, not media payloads. Unknown/legacy formats,
// corrupt headers and missing files have no duration; never estimate from text.
func dictationCachedDuration(path string) float64 {
	f, err := os.Open(path)
	if err != nil {
		return 0
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() {
		return 0
	}
	h := make([]byte, 44)
	if _, err = io.ReadFull(f, h); err != nil {
		return 0
	}
	u32 := func(i int) uint64 { return uint64(binary.LittleEndian.Uint32(h[i:])) }
	u16 := func(i int) uint64 { return uint64(binary.LittleEndian.Uint16(h[i:])) }
	if string(h[:4]) != "RIFF" || string(h[8:16]) != "WAVEfmt " || u32(16) != 16 || u16(20) != 1 || string(h[36:40]) != "data" {
		return 0
	}
	channels, rate, byteRate, align, bits, size := u16(22), u32(24), u32(28), u16(32), u16(34), u32(40)
	if channels == 0 || rate == 0 || byteRate == 0 || bits == 0 || bits%8 != 0 || align != channels*(bits/8) || byteRate != rate*align || size == 0 || size%align != 0 || u32(4) != 36+size || int64(44+size) != info.Size() {
		return 0
	}
	return float64(size) / float64(byteRate)
}
