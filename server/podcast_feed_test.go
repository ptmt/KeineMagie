package main

import (
	"context"
	"net/http"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPodcastSubscriptionDurableDiscoveryOnly(t *testing.T) {
	f := podcastFixtureFetcher(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/rss+xml")
		w.Write([]byte(`<rss><channel><title>Show</title><item><guid>one</guid><title>One</title><enclosure url="/a.mp3" type="audio/mpeg"/></item></channel></rss>`))
	})
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	p := podcastService{store: s, sourceFetcher: &f}
	sub, e := p.subscribe(context.Background(), "owner", "http://fixture.example/feed")
	if e != nil {
		t.Fatal(e)
	}
	again, e := p.subscribe(context.Background(), "owner", "http://fixture.example/feed")
	if e != nil || again.ID != sub.ID {
		t.Fatalf("idempotency %+v %v", again, e)
	}
	s, _ = openPodcastStore(s.lock.path)
	subs, e := s.subscriptions("owner")
	if e != nil || len(subs) != 1 || len(subs[0].Episodes) != 1 {
		t.Fatalf("durability %+v %v", subs, e)
	}
	if jobs, _ := s.list("owner"); len(jobs) != 0 {
		t.Fatal("discovery enqueued AI work")
	}
	if other, _ := s.subscriptions("other"); len(other) != 0 {
		t.Fatal("owner leak")
	}
	if _, e := s.subscription("other", sub.ID); e != errPodcastNotFound {
		t.Fatal("cross-owner lookup", e)
	}
	if e := s.removeSubscription("other", sub.ID); e != errPodcastNotFound {
		t.Fatal("cross-owner delete", e)
	}
	refreshed, e := s.saveSubscription("owner", sub.ID, podcastDiscovery{URL: sub.URL, Title: "Updated", Episodes: append(sub.Episodes, podcastEpisode{ID: "two", Title: "Two", URL: "http://fixture.example/b.mp3"})}, time.Now())
	if e != nil || len(refreshed.Episodes) != 2 {
		t.Fatalf("refresh: %+v %v", refreshed, e)
	}
	refreshed, e = s.saveSubscription("owner", sub.ID, podcastDiscovery{URL: sub.URL, Title: "Updated", Episodes: refreshed.Episodes}, time.Now())
	if e != nil || len(refreshed.Episodes) != 2 {
		t.Fatalf("refresh duplicate: %+v %v", refreshed, e)
	}
	if e := s.removeSubscription("owner", sub.ID); e != nil {
		t.Fatal(e)
	}
	if _, e := s.saveSubscription("owner", sub.ID, podcastDiscovery{URL: sub.URL, Title: "late", Episodes: sub.Episodes}, time.Now()); e != errPodcastNotFound {
		t.Fatal("late refresh resurrected deletion", e)
	}
}
func TestPodcastFeedBoundsAndAtom(t *testing.T) {
	base, _ := podcastURL("https://example.com/feed")
	for _, xml := range []string{`<!DOCTYPE rss [<!ENTITY x SYSTEM "http://127.0.0.1/secret">]><rss><channel><title>&x;</title></channel></rss>`, strings.Repeat("x", int(podcastDocumentBytes)+1), `<rss>` + strings.Repeat("<a>", 33) + strings.Repeat("</a>", 33) + `</rss>`} {
		if _, e := podcastParseFeed([]byte(xml), base); e == nil {
			t.Fatal("accepted unsafe/unbounded XML")
		}
	}
	atom := `<feed xmlns="http://www.w3.org/2005/Atom"><title>Atom</title><entry><id>1</id><title>One</title><link rel="enclosure" type="audio/mpeg" href="/a.mp3"/></entry><entry><id>2</id><link rel="enclosure" type="audio/mpeg" href="http://127.0.0.1/no"/></entry></feed>`
	got, e := podcastParseFeed([]byte(atom), base)
	if e != nil || got.Title != "Atom" || len(got.Episodes) != 1 {
		t.Fatalf("atom %+v %v", got, e)
	}
	many := `<rss><channel>`
	for i := 0; i < 100; i++ {
		many += `<item><guid>` + strings.Repeat("x", i+1) + `</guid><enclosure type="audio/mpeg" url="/` + strings.Repeat("a", i+1) + `.mp3"/></item>`
	}
	many += `</channel></rss>`
	got, e = podcastParseFeed([]byte(many), base)
	if e != nil || len(got.Episodes) != podcastFeedEpisodes {
		t.Fatalf("bounds %d %v", len(got.Episodes), e)
	}
}
