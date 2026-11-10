package main

import (
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPodcastMetadataLatestUsesDatesAndPersists(t *testing.T) {
	base, _ := podcastURL("https://example.com/feed")
	for _, art := range []string{`<image><url>https://example.com/cover.png?v=5</url></image>`, `<itunes:image xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" href="https://example.com/cover.png?v=5"/>`, `<logo>https://example.com/cover.png?v=5</logo>`} {
		xml := `<rss><channel>` + art + `<item><title>Older first</title><pubDate>Mon, 02 Nov 2026 10:00:00 +0000</pubDate><enclosure url="/old.mp3"/></item><item><title>Newest</title><pubDate>Tue, 10 Nov 2026 10:00:00 +0000</pubDate><enclosure url="/new.mp3"/></item></channel></rss>`
		if strings.HasPrefix(art, "<logo>") {
			xml = strings.ReplaceAll(strings.ReplaceAll(xml, "<rss><channel>", "<feed>"), "</channel></rss>", "</feed>")
		}
		got, err := podcastParseFeed([]byte(xml), base)
		if err != nil || got.ArtworkURL != "https://example.com/cover.png?v=5" || got.LatestEpisodeTitle != "Newest" {
			t.Fatalf("metadata %+v %v", got, err)
		}
		store, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
		sub, err := store.saveSubscription("owner", "", got, time.Now())
		if err != nil {
			t.Fatal(err)
		}
		reopened, _ := openPodcastStore(store.lock.path)
		saved, err := reopened.subscription("owner", sub.ID)
		if err != nil || saved.ArtworkURL != got.ArtworkURL || saved.LatestEpisodeTitle != got.LatestEpisodeTitle {
			t.Fatal("metadata not durable")
		}
	}
}
