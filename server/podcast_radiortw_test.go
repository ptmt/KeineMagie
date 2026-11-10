package main

import (
	"os"
	"testing"
)

// Public publisher fixture, fetched from the Radio RTW RSS feed on 2026-11-10.
// Discovery must remain independent of recognition's ten-minute duration cap.
func TestPodcastRadioRTWPublicFeed(t *testing.T) {
	b, err := os.ReadFile("testdata/radiortw.rss")
	if err != nil {
		t.Fatal(err)
	}
	base, _ := podcastURL("https://cdn.audiorella.com/podcasts/1615-radio-rtw/feed.rss")
	got, err := podcastParseFeed(b, base)
	if err != nil {
		t.Fatal(err)
	}
	if got.ArtworkURL != "https://cdn.audiorella.com/podcasts/1615-radio-rtw/1615_cover.jpg?v=5" || got.LatestEpisodeTitle != "The Nut Sisters" {
		t.Fatalf("missing public artwork/latest metadata: %+v", got)
	}
	if got.Title != "Radio RTW" || len(got.Episodes) != podcastFeedEpisodes {
		t.Fatalf("title=%q episodes=%d want=%d", got.Title, len(got.Episodes), podcastFeedEpisodes)
	}
}
