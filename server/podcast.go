package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"
)

func (p *podcastService) handle(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if r.Header.Get("Origin") != "" || cookieValue(r, browserCookie) != "" {
		token := cookieValue(r, browserCookie)
		s, e := p.cfg.auth.store.lookup(token, time.Now())
		if e != nil || s.Kind != "browser" {
			writeError(w, 401, "authentication required")
			return
		}
		if r.Method != "GET" && !newBrowserAuth(p.cfg).mutation(w, r, token) {
			return
		}
		r = r.Clone(r.Context())
		r.Header.Set("Authorization", "Bearer "+token)
	}
	owner, ok := p.cfg.provider.owner(w, r)
	if !ok {
		return
	}
	if !p.cfg.provider.allow(owner+"podcasts", 60) {
		writeError(w, 429, "podcast rate limited")
		return
	}
	suffix := strings.TrimPrefix(r.URL.Path, "/v1/podcasts")
	if p.handleSources(w, r, owner, suffix) {
		return
	}
	if suffix == "" || suffix == "/" {
		switch r.Method {
		case "GET":
			jobs, e := p.store.list(owner)
			if e != nil {
				writeError(w, 503, "podcast store unavailable")
				return
			}
			limits, e := configuredPodcastLimits()
			if e != nil {
				writeError(w, 503, "invalid podcast limits")
				return
			}
			writeJSON(w, 200, map[string]any{"items": jobs, "worker_available": p.ready() == nil, "supported_sources": []string{"direct_audio", "html_audio", "rss", "atom"}, "max_duration_seconds": limits.duration, "max_bytes": limits.bytes})
			return
		case "POST":
			if p.ready() != nil {
				writeError(w, 503, "local podcast worker unavailable; administrator must enable installed Whisper/ffmpeg worker")
				return
			}
			var input struct {
				URL    string `json:"url"`
				Source string `json:"source_language"`
			}
			d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
			defer r.Body.Close()
			d.DisallowUnknownFields()
			if d.Decode(&input) != nil || d.Decode(new(any)) != io.EOF {
				writeError(w, 400, "invalid JSON body")
				return
			}
			if input.Source != "de" && input.Source != "ru" {
				writeError(w, 400, "source_language must be de or ru")
				return
			}
			if _, e := podcastURL(input.URL); e != nil {
				writeError(w, 400, e.Error())
				return
			}
			// Fail before ingestion if this owner has not explicitly connected a provider.
			unlock, e := p.cfg.provider.lockOwner(r.Context(), owner)
			if e != nil {
				writeError(w, 408, "request canceled")
				return
			}
			c, e := p.cfg.provider.load(owner)
			unlock()
			if e != nil || c.AccessToken == "" {
				writeError(w, 503, "connect your personal ChatGPT account first")
				return
			}
			job, e := p.store.create(owner, input.URL, input.Source, time.Now())
			if e != nil {
				podcastHTTPError(w, e)
				return
			}
			writeJSON(w, 202, job)
			return
		default:
			writeError(w, 405, "method not allowed")
			return
		}
	}
	parts := strings.Split(strings.Trim(suffix, "/"), "/")
	if len(parts) > 2 || parts[0] == "" {
		writeError(w, 404, "podcast not found")
		return
	}
	id := parts[0]
	if len(parts) == 1 && r.Method == "GET" {
		jobs, e := p.store.list(owner)
		if e != nil {
			writeError(w, 503, "podcast store unavailable")
			return
		}
		for _, j := range jobs {
			if j.ID == id {
				writeJSON(w, 200, j)
				return
			}
		}
		writeError(w, 404, "podcast not found")
		return
	}
	action := ""
	if len(parts) == 2 && r.Method == "POST" && (parts[1] == "retry" || parts[1] == "cancel") {
		action = parts[1]
	}
	if len(parts) == 1 && r.Method == "DELETE" {
		action = "delete"
	}
	if action == "" {
		writeError(w, 405, "method not allowed")
		return
	}
	if action == "retry" && p.ready() != nil {
		writeError(w, 503, "local podcast worker unavailable")
		return
	}
	job, e := p.store.mutate(owner, id, action, time.Now())
	if e != nil {
		podcastHTTPError(w, e)
		return
	}
	if action == "delete" {
		w.WriteHeader(204)
		return
	}
	writeJSON(w, 200, job)
}
func podcastHTTPError(w http.ResponseWriter, e error) {
	if errors.Is(e, errPodcastNotFound) {
		writeError(w, 404, "podcast not found")
		return
	}
	if errors.Is(e, errPodcastLimit) {
		writeError(w, 429, "podcast budget reached: 2 active, 4 attempts/day, 30 retained per owner; 32 queued globally")
		return
	}
	writeError(w, 409, "podcast operation unavailable for this state")
}
