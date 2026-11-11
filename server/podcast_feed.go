package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"
)

type podcastSubscription struct {
	ID                 string           `json:"id"`
	URL                string           `json:"url"`
	Title              string           `json:"title"`
	Episodes           []podcastEpisode `json:"episodes"`
	ArtworkURL         string           `json:"artwork_url,omitempty"`
	LatestEpisodeTitle string           `json:"latest_episode_title,omitempty"`
	RefreshedAt        time.Time        `json:"refreshed_at"`
}
type podcastStoredSubscription struct {
	podcastSubscription
	Owner string `json:"owner"`
}

func (s *podcastStore) subscriptions(owner string) ([]podcastSubscription, error) {
	out := []podcastSubscription{}
	e := s.lock.locked(func() error {
		d, e := s.read()
		if e != nil {
			return e
		}
		for _, sub := range d.Subscriptions {
			if sub.Owner == owner {
				view := sub.podcastSubscription
				view.Episodes = append([]podcastEpisode(nil), view.Episodes...)
				for i := range view.Episodes {
					ep := &view.Episodes[i]
					for _, stored := range d.Jobs {
						j := storedPodcast(stored)
						if j.Owner != owner || !((j.FeedID == sub.ID && j.EpisodeID == ep.ID) || (j.FeedID == "" && j.URL == ep.URL)) {
							continue
						}
						if ep.Preparation == nil || podcastIdentityRank(j.State) > podcastIdentityRank(ep.Preparation.State) {
							j.Segments = nil
							ep.Preparation = &j
						}
					}
				}
				out = append(out, view)
			}
		}
		return nil
	})
	return out, e
}
func (s *podcastStore) subscription(owner, id string) (podcastSubscription, error) {
	subs, e := s.subscriptions(owner)
	if e != nil {
		return podcastSubscription{}, e
	}
	for _, sub := range subs {
		if sub.ID == id {
			return sub, nil
		}
	}
	return podcastSubscription{}, errPodcastNotFound
}
func (s *podcastStore) saveSubscription(owner, id string, discovery podcastDiscovery, now time.Time) (podcastSubscription, error) {
	var out podcastSubscription
	e := s.lock.locked(func() error {
		d, e := s.read()
		if e != nil {
			return e
		}
		count := 0
		for i := range d.Subscriptions {
			sub := &d.Subscriptions[i]
			if sub.Owner != owner {
				continue
			}
			count++
			if (id != "" && sub.ID == id) || (id == "" && sub.URL == discovery.URL) {
				// Keep bounded prior metadata across sliding feed windows, deduplicating both
				// GUID and enclosure. Discovery never reserves pipeline or translation quota.
				merged := []podcastEpisode{}
				ids, urls := map[string]bool{}, map[string]bool{}
				for _, batch := range [][]podcastEpisode{discovery.Episodes, sub.Episodes} {
					for _, ep := range batch {
						if !ids[ep.ID] && len(merged) < podcastFeedEpisodes {
							merged = append(merged, ep)
							ids[ep.ID] = true
							urls[ep.URL] = true
						}
					}
				}
				sub.URL = discovery.URL
				sub.Title = discovery.Title
				sub.ArtworkURL = discovery.ArtworkURL
				sub.LatestEpisodeTitle = discovery.LatestEpisodeTitle
				sub.Episodes = merged
				sub.RefreshedAt = now.UTC()
				out = sub.podcastSubscription
				return s.write(d)
			}
		}
		if id != "" {
			return errPodcastNotFound
		} // deletion fences an in-flight refresh
		if count >= 10 || len(d.Subscriptions) >= 100 {
			return errPodcastLimit
		}
		out = podcastSubscription{ID: randomAuthToken(), URL: discovery.URL, Title: discovery.Title, Episodes: discovery.Episodes, ArtworkURL: discovery.ArtworkURL, LatestEpisodeTitle: discovery.LatestEpisodeTitle, RefreshedAt: now.UTC()}
		d.Subscriptions = append(d.Subscriptions, podcastStoredSubscription{podcastSubscription: out, Owner: owner})
		return s.write(d)
	})
	return out, e
}
func (s *podcastStore) removeSubscription(owner, id string) error {
	return s.lock.locked(func() error {
		d, e := s.read()
		if e != nil {
			return e
		}
		for i, sub := range d.Subscriptions {
			if sub.Owner == owner && sub.ID == id {
				d.Subscriptions = append(d.Subscriptions[:i], d.Subscriptions[i+1:]...)
				return s.write(d)
			}
		}
		return errPodcastNotFound
	})
}
func (p *podcastService) discover(ctx context.Context, raw string) (podcastDiscovery, error) {
	f := podcastFetcher{}
	if p.sourceFetcher != nil {
		f = *p.sourceFetcher
	}
	return f.discover(ctx, raw)
}
func (p *podcastService) subscribe(ctx context.Context, owner, raw string) (podcastSubscription, error) {
	// Avoid a network fetch and preserve identity on repeated subscribe.
	subs, e := p.store.subscriptions(owner)
	if e != nil {
		return podcastSubscription{}, e
	}
	for _, sub := range subs {
		if sub.URL == raw {
			return sub, nil
		}
	}
	if len(subs) >= 10 {
		return podcastSubscription{}, errPodcastLimit
	}
	found, e := p.discover(ctx, raw)
	if e != nil {
		return podcastSubscription{}, e
	}
	if e = ctx.Err(); e != nil {
		return podcastSubscription{}, e
	}
	return p.store.saveSubscription(owner, "", found, time.Now())
}
func podcastDecodeURL(w http.ResponseWriter, r *http.Request) (string, error) {
	var input struct {
		URL string `json:"url"`
	}
	defer r.Body.Close()
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	d.DisallowUnknownFields()
	if d.Decode(&input) != nil || d.Decode(new(any)) != io.EOF {
		return "", errors.New("invalid JSON body")
	}
	if _, e := podcastURL(input.URL); e != nil {
		return "", e
	}
	return input.URL, nil
}
func (p *podcastService) handleSources(w http.ResponseWriter, r *http.Request, owner, suffix string) bool {
	if r.Method == "POST" && (suffix == "/discover" || suffix == "/subscriptions") && !p.cfg.provider.allow(owner+"podcast-feed-refresh", 6) {
		writeError(w, 429, "feed discovery rate limited")
		return true
	}
	if suffix == "/discover" {
		if r.Method != "POST" {
			writeError(w, 405, "method not allowed")
			return true
		}
		raw, e := podcastDecodeURL(w, r)
		if e != nil {
			writeError(w, 400, e.Error())
			return true
		}
		found, e := p.discover(r.Context(), raw)
		if e != nil {
			writeError(w, 400, e.Error())
			return true
		}
		writeJSON(w, 200, found)
		return true
	}
	if suffix != "/subscriptions" && !strings.HasPrefix(suffix, "/subscriptions/") {
		return false
	}
	parts := strings.Split(strings.TrimPrefix(suffix, "/subscriptions"), "/")
	if suffix == "/subscriptions" {
		switch r.Method {
		case "GET":
			subs, e := p.store.subscriptions(owner)
			if e != nil {
				writeError(w, 503, "podcast store unavailable")
			} else {
				writeJSON(w, 200, map[string]any{"items": subs, "refresh_mode": "manual"})
			}
		case "POST":
			raw, e := podcastDecodeURL(w, r)
			if e != nil {
				writeError(w, 400, e.Error())
				break
			}
			sub, e := p.subscribe(r.Context(), owner, raw)
			if e != nil {
				if errors.Is(e, errPodcastLimit) {
					podcastHTTPError(w, e)
				} else {
					writeError(w, 400, e.Error())
				}
				break
			}
			writeJSON(w, 200, sub)
		default:
			writeError(w, 405, "method not allowed")
		}
		return true
	}
	if len(parts) < 2 || len(parts) > 3 || parts[1] == "" {
		writeError(w, 404, "subscription not found")
		return true
	}
	sub, e := p.store.subscription(owner, parts[1])
	if e != nil {
		podcastHTTPError(w, e)
		return true
	}
	if len(parts) == 3 && parts[2] == "artwork" {
		p.handleArtwork(w, r, sub)
		return true
	}
	if len(parts) == 2 && r.Method == "DELETE" {
		if e = p.store.removeSubscription(owner, sub.ID); e != nil {
			podcastHTTPError(w, e)
		} else {
			w.WriteHeader(204)
		}
		return true
	}
	if len(parts) == 3 && parts[2] == "refresh" && r.Method == "POST" {
		// Bound repeated manual polling independently from read/progress polling.
		if !p.cfg.provider.allow(owner+"podcast-feed-refresh", 6) {
			writeError(w, 429, "feed refresh rate limited")
			return true
		}
		found, e := p.discover(r.Context(), sub.URL)
		if e != nil {
			writeError(w, 400, e.Error())
			return true
		}
		if r.Context().Err() != nil {
			writeError(w, 408, "request canceled")
			return true
		}
		sub, e = p.store.saveSubscription(owner, sub.ID, found, time.Now())
		if e != nil {
			podcastHTTPError(w, e)
		} else {
			writeJSON(w, 200, sub)
		}
		return true
	}
	writeError(w, 405, "method not allowed")
	return true
}
