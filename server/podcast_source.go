package main

import (
	"context"
	"encoding/xml"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"golang.org/x/net/html"
)

const podcastDocumentBytes int64 = 2 << 20
const podcastFeedEpisodes = 50

var errPodcastNoAudio = errors.New("no extractable public audio: use an episode with HTML audio/og:audio or a public RSS/Atom feed; JavaScript, Spotify/Apple DRM and sign-in media are not supported")

type podcastEpisode struct {
	ID          string      `json:"id"`
	Title       string      `json:"title"`
	URL         string      `json:"url"`
	Published   string      `json:"published,omitempty"`
	Preparation *podcastJob `json:"preparation,omitempty"`
}
type podcastDiscovery struct {
	URL                string           `json:"url"`
	Title              string           `json:"title"`
	Episodes           []podcastEpisode `json:"episodes"`
	ArtworkURL         string           `json:"artwork_url,omitempty"`
	LatestEpisodeTitle string           `json:"latest_episode_title,omitempty"`
}

func podcastReference(base *url.URL, raw string) (*url.URL, error) {
	u, e := url.Parse(strings.TrimSpace(raw))
	if e != nil || raw == "" {
		return nil, errPodcastNoAudio
	}
	return podcastURL(base.ResolveReference(u).String())
}
func podcastDocument(ctx context.Context, u *url.URL, client *http.Client) (*http.Response, error) {
	if _, e := podcastURL(u.String()); e != nil {
		return nil, e
	}
	req, e := http.NewRequestWithContext(ctx, "GET", u.String(), nil)
	if e != nil {
		return nil, e
	}
	req.Header.Set("Accept", "text/html, application/rss+xml, application/atom+xml, application/xml, audio/*, application/octet-stream")
	resp, e := client.Do(req)
	if e != nil {
		return nil, errors.New("source fetch failed (destination, redirect, DNS or network policy)")
	}
	if resp.StatusCode != 200 {
		resp.Body.Close()
		return nil, errors.New("source unavailable")
	}
	return resp, nil
}
func podcastReadDocument(resp *http.Response) ([]byte, error) {
	if resp.ContentLength > podcastDocumentBytes {
		return nil, errors.New("source document exceeds 2 MiB")
	}
	b, e := io.ReadAll(io.LimitReader(resp.Body, podcastDocumentBytes+1))
	if e != nil {
		return nil, e
	}
	if int64(len(b)) > podcastDocumentBytes {
		return nil, errors.New("source document exceeds 2 MiB")
	}
	return b, nil
}
func podcastHTML(b []byte, base *url.URL) (audio, feed *url.URL) {
	z := html.NewTokenizer(strings.NewReader(string(b)))
	audioDepth := false
	for tokens := 0; tokens < 100000; tokens++ {
		tt := z.Next()
		if tt == html.ErrorToken {
			return
		}
		if tt == html.EndTagToken {
			name, _ := z.TagName()
			if string(name) == "audio" {
				audioDepth = false
			}
			continue
		}
		if tt != html.StartTagToken && tt != html.SelfClosingTagToken {
			continue
		}
		t := z.Token()
		a := map[string]string{}
		for _, v := range t.Attr {
			a[strings.ToLower(v.Key)] = v.Val
		}
		var candidate string
		if t.Data == "audio" {
			audioDepth = true
			candidate = a["src"]
		}
		if t.Data == "source" && audioDepth {
			candidate = a["src"]
		}
		if t.Data == "meta" && (a["property"] == "og:audio" || a["property"] == "og:audio:url" || a["property"] == "og:audio:secure_url") {
			candidate = a["content"]
		}
		if audio == nil && candidate != "" {
			audio, _ = podcastReference(base, candidate)
		}
		if feed == nil && t.Data == "link" && (a["type"] == "application/rss+xml" || a["type"] == "application/atom+xml") {
			for _, rel := range strings.Fields(strings.ToLower(a["rel"])) {
				if rel == "alternate" {
					feed, _ = podcastReference(base, a["href"])
				}
			}
		}
	}
	return
}
func podcastResolveAudio(ctx context.Context, u *url.URL, client *http.Client) (*url.URL, error) {
	resp, e := podcastDocument(ctx, u, client)
	if e != nil {
		return nil, e
	}
	defer resp.Body.Close()
	mime := strings.ToLower(strings.Split(resp.Header.Get("Content-Type"), ";")[0])
	if strings.HasPrefix(mime, "audio/") || mime == "application/octet-stream" {
		return resp.Request.URL, nil
	}
	if mime != "text/html" && mime != "application/xhtml+xml" {
		return nil, errPodcastNoAudio
	}
	b, e := podcastReadDocument(resp)
	if e != nil {
		return nil, e
	}
	media, _ := podcastHTML(b, resp.Request.URL)
	if media == nil {
		return nil, errPodcastNoAudio
	}
	return media, nil
}
func (f podcastFetcher) discover(ctx context.Context, raw string) (podcastDiscovery, error) {
	u, e := podcastURL(raw)
	if e != nil {
		return podcastDiscovery{}, e
	}
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	client := f.client()
	defer client.CloseIdleConnections()
	for step := 0; step < 2; step++ {
		resp, e := podcastDocument(ctx, u, client)
		if e != nil {
			return podcastDiscovery{}, e
		}
		b, e := podcastReadDocument(resp)
		resp.Body.Close()
		if e != nil {
			return podcastDiscovery{}, e
		}
		u = resp.Request.URL
		mime := strings.ToLower(strings.Split(resp.Header.Get("Content-Type"), ";")[0])
		if mime == "text/html" || mime == "application/xhtml+xml" {
			_, feed := podcastHTML(b, u)
			if feed == nil {
				return podcastDiscovery{}, errPodcastNoAudio
			}
			u = feed
			continue
		}
		return podcastParseFeed(b, u)
	}
	return podcastDiscovery{}, errors.New("feed discovery limited to one HTML alternate link")
}

// encoding/xml never resolves external entities. Directives/DTDs are rejected
// outright, with independent byte, token, depth and retained episode bounds.
func podcastParseFeed(b []byte, base *url.URL) (podcastDiscovery, error) {
	out := podcastDiscovery{URL: base.String(), Episodes: []podcastEpisode{}}
	if int64(len(b)) > podcastDocumentBytes {
		return out, errors.New("feed exceeds 2 MiB")
	}
	d := xml.NewDecoder(strings.NewReader(string(b)))
	depth, itemDepth := 0, 0
	field := ""
	var entry podcastEpisode
	seenID, seenURL := map[string]bool{}, map[string]bool{}
	root := ""
	var latest time.Time
	imageDepth := 0
	for tokens := 0; tokens < 200000; tokens++ {
		tok, e := d.Token()
		if e == io.EOF {
			if root != "rss" && root != "feed" {
				return out, errors.New("RSS or Atom feed required")
			}
			if len(out.Episodes) == 0 {
				return out, errPodcastNoAudio
			}
			return out, nil
		}
		if e != nil {
			return out, errors.New("invalid feed XML")
		}
		switch v := tok.(type) {
		case xml.Directive:
			return out, errors.New("XML directives and external entities are not supported")
		case xml.StartElement:
			depth++
			if depth > 32 {
				return out, errors.New("feed XML too deeply nested")
			}
			name := v.Name.Local
			if itemDepth == 0 && name == "image" && depth <= 3 {
				imageDepth = depth
				for _, attr := range v.Attr {
					if attr.Name.Local == "href" {
						if u, err := podcastReference(base, attr.Value); err == nil {
							out.ArtworkURL = u.String()
						}
					}
				}
			}
			if root == "" {
				root = name
			}
			if (name == "item" || name == "entry") && itemDepth == 0 {
				itemDepth = depth
				entry = podcastEpisode{}
			}
			field = ""
			if itemDepth > 0 && depth == itemDepth+1 {
				switch name {
				case "guid", "id", "title", "pubDate", "published", "updated":
					// RSS often repeats title as itunes:title; it is not another chunk.
					if v.Name.Space == "" || v.Name.Space == "http://www.w3.org/2005/Atom" {
						field = name
					}
				}
				if name == "enclosure" || name == "link" {
					a := map[string]string{}
					for _, attr := range v.Attr {
						a[attr.Name.Local] = attr.Value
					}
					raw := a["url"]
					if name == "link" {
						if a["rel"] != "enclosure" {
							break
						}
						raw = a["href"]
					}
					mime := strings.ToLower(a["type"])
					if mime == "" || strings.HasPrefix(mime, "audio/") || mime == "application/octet-stream" {
						if u, e := podcastReference(base, raw); e == nil && entry.URL == "" {
							entry.URL = u.String()
						}
					}
				}
			} else if itemDepth == 0 && ((name == "url" && imageDepth > 0 && depth == imageDepth+1) || ((name == "logo" || name == "icon") && depth == 2)) {
				field = "artwork"
			} else if itemDepth == 0 && name == "title" && depth <= 3 {
				field = "feedTitle"
			}
		case xml.CharData:
			text := string(v)
			if len(text) > 4096 {
				text = text[:4096]
			}
			appendBound := func(dst *string) {
				if len(*dst)+len(text) <= 4096 {
					*dst += text
				}
			}
			switch field {
			case "artwork":
				if u, err := podcastReference(base, strings.TrimSpace(text)); err == nil {
					out.ArtworkURL = u.String()
				}
			case "title":
				appendBound(&entry.Title)
			case "guid", "id":
				appendBound(&entry.ID)
			case "pubDate", "published", "updated":
				appendBound(&entry.Published)
			case "feedTitle":
				appendBound(&out.Title)
			}
		case xml.EndElement:
			if depth == itemDepth && itemDepth > 0 {
				entry.ID = strings.TrimSpace(entry.ID)
				entry.Title = strings.TrimSpace(entry.Title)
				entry.Published = strings.TrimSpace(entry.Published)
				if entry.URL != "" {
					published := podcastPublished(entry.Published)
					if out.LatestEpisodeTitle == "" || (!published.IsZero() && (latest.IsZero() || published.After(latest))) {
						out.LatestEpisodeTitle = entry.Title
						latest = published
					}
				}
				if entry.ID == "" {
					entry.ID = entry.URL
				}
				if entry.URL != "" && !seenID[entry.ID] && len(out.Episodes) < podcastFeedEpisodes {
					seenID[entry.ID] = true
					seenURL[entry.URL] = true
					// Opaque bounded ID, never expose arbitrary GUIDs as URL path identifiers.
					entry.ID = sessionHash(entry.ID)
					out.Episodes = append(out.Episodes, entry)
				}
				itemDepth = 0
			}
			depth--
			if depth < imageDepth {
				imageDepth = 0
			}
			field = ""
		}
	}
	return out, errors.New("feed XML token limit exceeded")
}

func podcastPublished(raw string) time.Time {
	for _, layout := range []string{time.RFC3339, time.RFC1123Z, time.RFC1123, time.RFC822Z, time.RFC822} {
		if value, err := time.Parse(layout, raw); err == nil {
			return value
		}
	}
	return time.Time{}
}
