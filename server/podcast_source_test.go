package main

import (
	"context"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Real HTTP fixture, reachable only through a per-test validated-IP dial seam.
func podcastFixtureFetcher(t *testing.T, handler http.HandlerFunc) podcastFetcher {
	t.Helper()
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	target := strings.TrimPrefix(srv.URL, "http://")
	return podcastFetcher{
		lookup: func(context.Context, string) ([]net.IPAddr, error) {
			return []net.IPAddr{{IP: net.ParseIP("93.184.216.34")}}, nil
		},
		dial: func(ctx context.Context, network, address string) (net.Conn, error) {
			if address != "93.184.216.34:80" {
				t.Errorf("not pinned to validated IP: %s", address)
			}
			return (&net.Dialer{}).DialContext(ctx, network, target)
		},
	}
}
func TestPodcastHTMLSourceFetch(t *testing.T) {
	f := podcastFixtureFetcher(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/episode":
			w.Header().Set("Content-Type", "text/html")
			w.Write([]byte(`<html><audio><source src="media/audio.mp3" type="audio/mpeg"></audio></html>`))
		case "/media/audio.mp3":
			w.Header().Set("Content-Type", "audio/mpeg")
			w.Write([]byte("fixture audio bytes"))
		default:
			http.NotFound(w, r)
		}
	})
	dest := filepath.Join(t.TempDir(), "audio")
	if err := f.fetch(context.Background(), "http://fixture.example/episode", dest); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(dest)
	if string(b) != "fixture audio bytes" {
		t.Fatalf("audio=%q", b)
	}
}
func TestPodcastRSSDiscovery(t *testing.T) {
	f := podcastFixtureFetcher(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/show" {
			w.Header().Set("Content-Type", "text/html")
			w.Write([]byte(`<link rel="alternate" type="application/rss+xml" href="/feed">`))
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		w.Write([]byte(`<rss><channel><title>Learn German</title><item><guid>one</guid><title>First</title><enclosure url="audio.mp3" type="audio/mpeg"/></item><item><guid>one</guid><enclosure url="audio.mp3" type="audio/mpeg"/></item></channel></rss>`))
	})
	got, err := f.discover(context.Background(), "http://fixture.example/show")
	if err != nil {
		t.Fatal(err)
	}
	if got.Title != "Learn German" || len(got.Episodes) != 1 || got.Episodes[0].URL != "http://fixture.example/audio.mp3" {
		t.Fatalf("%+v", got)
	}
	u, _ := url.Parse(got.URL)
	if u.Path != "/feed" {
		t.Fatal(got.URL)
	}
}
