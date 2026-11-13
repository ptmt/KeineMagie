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
	if p.handlePermalink(w, r, owner, suffix) {
		return
	}
	if p.handleSources(w, r, owner, suffix) {
		return
	}
	if suffix == "" || suffix == "/" {
		switch r.Method {
		case "GET":
			jobs, ownerLimits, e := p.store.listWithLimits(owner, time.Now())
			if e != nil {
				writeError(w, 503, "podcast store unavailable")
				return
			}
			// Learning readiness must not hide an independent saved transcript.
			_ = p.cfg.podcastCoverage(owner, jobs)
			limits, e := configuredPodcastLimits()
			if e != nil {
				writeError(w, 503, "invalid podcast limits")
				return
			}

			writeJSON(w, 200, map[string]any{"items": jobs, "limits": ownerLimits, "worker_available": p.ready() == nil, "supported_sources": []string{"direct_audio", "html_audio", "rss", "atom"}, "max_duration_seconds": limits.duration, "max_bytes": limits.bytes})
			return
		case "POST":
			var input struct {
				URL       string `json:"url"`
				Source    string `json:"source_language"`
				FeedID    string `json:"feed_id,omitempty"`
				EpisodeID string `json:"episode_id,omitempty"`
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
			if input.FeedID == "" && input.EpisodeID == "" {
				if _, e := podcastURL(input.URL); e != nil {
					writeError(w, 400, e.Error())
					return
				}
			} else {
				if _, e := p.store.subscription(owner, input.FeedID); e != nil {
					podcastHTTPError(w, e)
					return
				}
				// Feed identity uses only server-owned metadata, never caller aliases.
				input.URL = ""
			}
			admit := func() error {
				if p.ready() != nil {
					writeError(w, 503, "local podcast worker unavailable")
					return errors.New("admission rejected")
				}
				// Credentials are atomically replaced on disk. Do not take the owner
				// lock under the podcast lock: translation takes them in reverse order.
				c, e := p.cfg.provider.load(owner)
				if e != nil || c.AccessToken == "" {
					writeError(w, 503, "connect your personal ChatGPT account first")
					return errors.New("admission rejected")
				}
				return nil
			}
			raw := input.URL
			existing, e := p.store.episode(owner, raw, input.Source, input.FeedID, input.EpisodeID, input.URL, time.Now(), true, nil)
			if e != nil {
				podcastHTTPError(w, e)
				return
			}
			if existing.ID != "" {
				writeJSON(w, 202, existing)
				return
			}
			if input.FeedID == "" && input.EpisodeID == "" {
				// Cached validated aliases let repeated requests survive source outages.
				jobs, err := p.store.list(owner)
				if err != nil {
					podcastHTTPError(w, err)
					return
				}
				for _, j := range jobs {
					if j.SourceLanguage == input.Source && (j.SourceURL == raw || j.URL == raw) {
						writeJSON(w, 202, j)
						return
					}
				}
				raw, e = p.resolveImport(r.Context(), raw)
				if e != nil {
					writeError(w, 400, "source audio unavailable")
					return
				}
			}
			admissionRejected := false
			job, e := p.store.episode(owner, raw, input.Source, input.FeedID, input.EpisodeID, input.URL, time.Now(), false, func() error {
				err := admit()
				admissionRejected = err != nil
				return err
			})
			if e != nil {
				if !admissionRejected {
					podcastHTTPError(w, e)
				}
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
		// Learning readiness must not hide an independent saved transcript.
		_ = p.cfg.podcastCoverage(owner, jobs)
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
	var quota *podcastLimitError
	if errors.As(e, &quota) {
		writePodcastLimit(w, quota)
		return
	}
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
