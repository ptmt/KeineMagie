package main

import (
	"context"
	"path"
	"strings"
	"time"
)

func (p *podcastService) resolveImport(ctx context.Context, raw string) (string, error) {
	u, e := podcastURL(raw)
	if e != nil {
		return "", e
	}
	// Obvious media URLs need no metadata fetch. The worker still validates
	// DNS, redirects, MIME and bytes before decoding; suffix is not trust.
	switch strings.ToLower(path.Ext(u.Path)) {
	case ".mp3", ".m4a", ".aac", ".wav", ".ogg", ".opus", ".flac", ".aiff":
		return u.String(), nil
	}
	f := podcastFetcher{}
	if p.sourceFetcher != nil {
		f = *p.sourceFetcher
	}
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	client := f.client()
	defer client.CloseIdleConnections()
	audio, e := podcastResolveAudio(ctx, u, client)
	if e != nil {
		return "", e
	}
	return audio.String(), nil
}

// Exact validated URLs retain query ordering/values; never strip signed tokens.
func podcastSameEpisode(a, b podcastJob) bool {
	if a.Owner != b.Owner || a.SourceLanguage != b.SourceLanguage {
		return false
	}
	if a.FeedID != "" && b.FeedID != "" {
		return a.FeedID == b.FeedID && a.EpisodeID == b.EpisodeID
	}
	return a.URL == b.URL
}
func podcastIdentityRank(state string) int {
	switch state {
	case "completed":
		return 5
	case "fetching", "transcribing", "translating":
		return 4
	case "queued":
		return 3
	default:
		return 1
	}
}
