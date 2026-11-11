package main

import (
	"net/http"
	"strconv"
	"time"
)

// Counts are restricted to the authenticated owner. Global counts and owner
// identifiers must never be exposed by this status object.
type podcastOwnerLimits struct {
	MaxActive      int       `json:"max_active"`
	Active         int       `json:"active"`
	MaxRetained    int       `json:"max_retained"`
	Retained       int       `json:"retained"`
	DailyLimit     int       `json:"daily_limit"`
	DailyAttempts  int       `json:"daily_attempts"`
	DailyRemaining int       `json:"daily_remaining"`
	ResetsAt       time.Time `json:"resets_at"`
}

func podcastLimitsFor(d podcastData, owner string, now time.Time) podcastOwnerLimits {
	utc := now.UTC()
	out := podcastOwnerLimits{MaxActive: 2, MaxRetained: 30, DailyLimit: 4, ResetsAt: time.Date(utc.Year(), utc.Month(), utc.Day()+1, 0, 0, 0, 0, time.UTC)}
	for _, j := range d.Jobs {
		if j.Owner == owner {
			out.Retained++
			if podcastActive(j.State) {
				out.Active++
			}
		}
	}
	if q := d.Budgets[sessionHash(owner)]; q.Day == utc.Format("2006-01-02") {
		out.DailyAttempts = q.Attempts
	}
	out.DailyRemaining = max(0, out.DailyLimit-out.DailyAttempts)
	return out
}

type podcastLimitError struct {
	Code       string             `json:"code"`
	Message    string             `json:"error"`
	Limit      int                `json:"limit"`
	Remaining  int                `json:"remaining"`
	RetryAfter int                `json:"retry_after,omitempty"`
	Limits     podcastOwnerLimits `json:"limits"`
}

func (e *podcastLimitError) Error() string { return e.Message }
func (e *podcastLimitError) Unwrap() error { return errPodcastLimit }
func podcastCheckAdmission(d podcastData, owner string, now time.Time) error {
	limits := podcastLimitsFor(d, owner, now)
	code, message, limit := "", "", 0
	switch {
	case limits.Active >= limits.MaxActive:
		code, message, limit = "podcast_active_limit", "Two podcast preparations are already active; wait or cancel one.", 2
	case limits.Retained >= limits.MaxRetained:
		code, message, limit = "podcast_storage_limit", "Thirty podcast preparations are retained; delete an unneeded inactive item.", 30
	default:
		active := 0
		for _, j := range d.Jobs {
			if podcastActive(j.State) {
				active++
			}
		}
		if active >= 32 {
			code, message, limit = "podcast_global_active_limit", "The podcast queue is full; try again after current work finishes.", 32
		} else if len(d.Jobs) >= 500 {
			code, message, limit = "podcast_global_storage_limit", "Podcast storage is full; contact the administrator.", 500
		} else if limits.DailyRemaining == 0 {
			code, message, limit = "podcast_daily_limit", "All four podcast admissions for today have been used, including failed or deleted preparations; resets at 00:00 UTC. This is separate from the personal translation budget.", 4
		}
	}
	if code == "" {
		return nil
	}
	e := &podcastLimitError{Code: code, Message: message, Limit: limit, Limits: limits}
	if code == "podcast_daily_limit" {
		e.RetryAfter = int((limits.ResetsAt.Sub(now) + time.Second - 1) / time.Second)
	}
	return e
}
func writePodcastLimit(w http.ResponseWriter, e *podcastLimitError) {
	if e.RetryAfter > 0 {
		w.Header().Set("Retry-After", strconv.Itoa(e.RetryAfter))
	}
	writeJSON(w, 429, e)
}
