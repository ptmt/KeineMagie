package main

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPodcastFeedAuthorIsDurablePlainMetadata(t *testing.T) {
	base, _ := podcastURL("https://example.com/feed")
	for _, xml := range []string{
		`<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>Feed</title><itunes:author>The Nut Sisters</itunes:author><item><author>Episode Author</author><enclosure url="/audio.mp3"/></item></channel></rss>`,
		`<feed xmlns="http://www.w3.org/2005/Atom"><title>Feed</title><author><name>The Nut Sisters</name></author><entry><author><name>Episode Author</name></author><link rel="enclosure" href="/audio.mp3"/></entry></feed>`,
	} {
		got, e := podcastParseFeed([]byte(xml), base)
		if e != nil {
			t.Fatal(e)
		}
		encoded, _ := json.Marshal(got)
		var fields map[string]any
		_ = json.Unmarshal(encoded, &fields)
		if fields["author"] != "The Nut Sisters" {
			t.Fatalf("missing feed author: %s", encoded)
		}
		store, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
		sub, e := store.saveSubscription("owner", "", got, time.Now())
		if e != nil {
			t.Fatal(e)
		}
		saved, _ := store.subscription("owner", sub.ID)
		encoded, _ = json.Marshal(saved)
		_ = json.Unmarshal(encoded, &fields)
		if fields["author"] != "The Nut Sisters" {
			t.Fatal("author not durable")
		}
	}
}

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
