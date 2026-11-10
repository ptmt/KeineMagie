package main

import (
	"strings"
	"testing"
)

func TestPodcastFeedRejectsSilentAllUnusableAudio(t *testing.T) {
	base, _ := podcastURL("https://example.com/feed")
	for _, enclosure := range []string{`https://example.com/a.mp3?token=private`, `http://127.0.0.1/a.mp3`} {
		_, err := podcastParseFeed([]byte(`<rss><channel><item><enclosure type="audio/mpeg" url="`+enclosure+`"/></item></channel></rss>`), base)
		if err == nil || !strings.Contains(err.Error(), "no extractable public audio") {
			t.Fatalf("expected explicit discovery error, got %v", err)
		}
	}
}

func TestPodcastPublicQueryBounds(t *testing.T) {
	for _, query := range []string{"v=2&awEpisodeId=256848&awCollectionId=julephosting_68ff5ade7890b", "v=5"} {
		if _, err := podcastURL("https://example.com/a?" + query); err != nil {
			t.Fatal(err)
		}
	}
	for _, query := range []string{"token=secret", "v=secret", "v=1&v=2", "awCollectionId=https%3A%2F%2F127.0.0.1", "awEpisodeId=" + strings.Repeat("1", 65), "v=%zz"} {
		if _, err := podcastURL("https://example.com/a?" + query); err == nil {
			t.Fatal("accepted unsafe query")
		}
	}
}
