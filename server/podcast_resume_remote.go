package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"io"
	"math"
	"net/http"
	"os"
	"strconv"
	"strings"
)

func (c *podcastRemote) transcribeResumable(ctx context.Context, path string, j *podcastJob, save func() error) error {
	invalid := errors.New("invalid resumable worker transcript")
	limits, e := configuredPodcastLimits()
	if e != nil {
		return e
	}
	if j.Resume == nil || (j.SourceLanguage != "de" && j.SourceLanguage != "ru") {
		return invalid
	}
	// A final short window may have been persisted just before disconnection.
	// Replay only that window, replacing its old segments rather than duplicating.
	offset := int(math.Floor(j.Resume.End/600)) * 600
	if offset < 0 || offset > limits.duration {
		return invalid
	}
	base := make([]podcastSegment, 0, len(j.Segments))
	for _, s := range j.Segments {
		if s.Start < float64(offset) {
			base = append(base, s)
		}
	}
	f, e := os.Open(path)
	if e != nil {
		return errors.New("staged audio unavailable")
	}
	defer f.Close()
	st, e := f.Stat()
	if e != nil || !st.Mode().IsRegular() || st.Size() != j.Resume.Bytes || st.Size() > limits.bytes {
		return invalid
	}
	req, e := http.NewRequestWithContext(ctx, "POST", c.endpoint+"/internal/podcast/transcribe", f)
	if e != nil {
		return invalid
	}
	req.ContentLength = st.Size()
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("X-Podcast-Version", "1")
	req.Header.Set("X-Podcast-Language", j.SourceLanguage)
	req.Header.Set("Content-Type", "application/octet-stream")
	req.Header.Set("Accept", "application/x-ndjson")
	req.Header.Set("X-Resume-Offset", strconv.Itoa(offset))
	req.Header.Set("X-Podcast-Job-ID", j.ID)
	req.Header.Set("X-Media-SHA256", j.Resume.Digest)
	resp, e := c.http.Do(req)
	if e != nil {
		return errors.New("private transcription worker unavailable")
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 || strings.TrimSpace(strings.Split(resp.Header.Get("Content-Type"), ";")[0]) != "application/x-ndjson" {
		return errors.New("private worker requires resumable protocol")
	}
	scanner := bufio.NewScanner(io.LimitReader(resp.Body, podcastMaxResponseBytes+1))
	scanner.Buffer(make([]byte, 4096), podcastMaxResponseBytes)
	totalWire := 0
	end := float64(offset)
	index := offset / 600
	chars := 0
	for _, s := range base {
		chars += runeCount(s.Text)
	}
	partial := false
	for scanner.Scan() {
		totalWire += len(scanner.Bytes()) + 1
		if totalWire > podcastMaxResponseBytes {
			return invalid
		}
		var event struct {
			Type     string           `json:"type"`
			Index    int              `json:"chunk_index"`
			End      float64          `json:"end_seconds"`
			Segments []podcastSegment `json:"segments"`
			Duration float64          `json:"duration_seconds"`
			Language string           `json:"language"`
		}
		if json.Unmarshal(scanner.Bytes(), &event) != nil {
			return invalid
		}
		switch event.Type {
		case "checkpoint":
			if partial || event.Index != index || math.IsNaN(event.End) || math.IsInf(event.End, 0) || event.End <= end || event.End > float64((index+1)*600) || event.End > float64(limits.duration) {
				return invalid
			}
			previous := end
			for i := range event.Segments {
				s := &event.Segments[i]
				s.Text = strings.TrimSpace(s.Text)
				s.Translation = ""
				chars += runeCount(s.Text)
				if s.Text == "" || runeCount(s.Text) > podcastMaxSegmentCharacters || chars > podcastMaxCharacters || math.IsNaN(s.Start) || math.IsNaN(s.End) || math.IsInf(s.Start, 0) || math.IsInf(s.End, 0) || s.Start < previous || s.End <= s.Start || s.End > event.End {
					return invalid
				}
				previous = s.End
			}
			if len(base)+len(event.Segments) > podcastMaxSegments {
				return invalid
			}
			base = append(base, event.Segments...)
			end = event.End
			partial = end < float64((index+1)*600)
			index++
			j.Segments = append([]podcastSegment{}, base...)
			j.Resume.End = end
			j.Progress = 20 + int(end*29/float64(limits.duration))
			if e = save(); e != nil {
				return e
			}
		case "complete":
			if event.Language != j.SourceLanguage || event.Duration != end || end <= 0 || end > float64(limits.duration) || len(base) == 0 {
				return invalid
			}
			j.Segments = base
			j.Resume.Complete = true
			return save()
		case "error":
			return errors.New("worker recognition failed; saved progress retained")
		default:
			return invalid
		}
	}
	return errors.New("worker disconnected before completion; saved progress retained")
}
