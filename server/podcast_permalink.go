package main

import (
	"net/http"
	"regexp"
	"strings"
	"time"
)

var podcastPermalinkPattern = regexp.MustCompile(`^[a-z0-9]+(?:-[a-z0-9]+)*-([a-f0-9]{12})$`)

// The readable slug is cosmetic; the suffix is a lookup key, NOT authorization.
// Callers must supply only jobs belonging to the authenticated owner.
func resolvePodcastPermalink(jobs []podcastJob, suffix string) (podcastJob, error) {
	if !regexp.MustCompile(`^[a-f0-9]{12}$`).MatchString(suffix) {
		return podcastJob{}, errPodcastNotFound
	}
	var found podcastJob
	count := 0
	for _, job := range jobs {
		if sessionHash(job.ID)[:12] == suffix {
			found = job
			count++
		}
	}
	if count != 1 {
		return podcastJob{}, errPodcastNotFound
	}
	return found, nil
}

func (p *podcastService) handlePermalink(w http.ResponseWriter, r *http.Request, owner, suffix string) bool {
	if !strings.HasPrefix(suffix, "/episodes/") {
		return false
	}
	if r.Header.Get("Origin") == "" && cookieValue(r, browserCookie) == "" {
		if session, e := p.cfg.auth.store.lookup(bearerSession(r), time.Now()); e == nil && session.Kind == "browser" {
			writeError(w, 401, "browser cookie required")
			return true
		}
	}
	if r.Method != "GET" {
		writeError(w, 405, "method not allowed")
		return true
	}
	match := podcastPermalinkPattern.FindStringSubmatch(strings.TrimPrefix(suffix, "/episodes/"))
	if match == nil {
		writeError(w, 404, "podcast not found")
		return true
	}
	jobs, e := p.store.list(owner)
	if e != nil {
		writeError(w, 503, "podcast store unavailable")
		return true
	}
	job, e := resolvePodcastPermalink(jobs, match[1])
	if e != nil {
		podcastHTTPError(w, e)
		return true
	}
	writeJSON(w, 200, job)
	return true
}

func isPodcastEpisodePath(path string) bool {
	return strings.HasPrefix(path, "/podcasts/episodes/") && podcastPermalinkPattern.MatchString(strings.TrimPrefix(path, "/podcasts/episodes/"))
}
