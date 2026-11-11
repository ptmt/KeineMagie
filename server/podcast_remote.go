package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"math"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

// Only administrator configuration reaches this transport. Source fetches never
// use it. Every resolved address must be private/loopback; no proxy or redirects.
type podcastRemote struct {
	endpoint, token string
	http            *http.Client
}

func newPodcastRemote(endpoint, tokenFile string) (*podcastRemote, error) {
	u, e := url.Parse(endpoint)
	if e != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Hostname() == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") {
		return nil, errors.New("invalid private podcast worker endpoint")
	}
	info, e := os.Lstat(tokenFile)
	if e != nil || !info.Mode().IsRegular() || info.Mode().Perm() != 0600 || info.Size() > 256 {
		return nil, errors.New("podcast worker token must be a regular 0600 file")
	}
	b, e := os.ReadFile(tokenFile)
	token := strings.TrimSpace(string(b))
	if e != nil || len(token) != 64 || strings.IndexFunc(token, func(r rune) bool { return !(r >= '0' && r <= '9' || r >= 'a' && r <= 'f') }) >= 0 {
		return nil, errors.New("podcast worker token must be 32 random bytes encoded as lowercase hex")
	}
	tr := &http.Transport{Proxy: nil, DisableKeepAlives: true, ResponseHeaderTimeout: podcastWorkerTimeout, TLSHandshakeTimeout: 10 * time.Second}
	tr.DialContext = func(ctx context.Context, network, address string) (net.Conn, error) {
		host, port, e := net.SplitHostPort(address)
		if e != nil {
			return nil, errors.New("worker address invalid")
		}
		ips, e := net.DefaultResolver.LookupIPAddr(ctx, host)
		if e != nil || len(ips) == 0 {
			return nil, errors.New("private worker resolution failed")
		}
		for _, a := range ips {
			if a.Zone != "" || (!a.IP.IsPrivate() && !a.IP.IsLoopback()) {
				return nil, errors.New("worker must resolve exclusively to private addresses")
			}
		}
		d := net.Dialer{Timeout: 10 * time.Second}
		return d.DialContext(ctx, network, net.JoinHostPort(ips[0].IP.String(), port))
	}
	return &podcastRemote{strings.TrimRight(endpoint, "/"), token, &http.Client{Transport: tr, Timeout: podcastWorkerTimeout, CheckRedirect: func(*http.Request, []*http.Request) error { return errors.New("worker redirects forbidden") }}}, nil
}
func (c *podcastRemote) request(ctx context.Context, method, path string, body io.Reader, language string, length int64) ([]byte, error) {
	r, e := http.NewRequestWithContext(ctx, method, c.endpoint+path, body)
	if e != nil {
		return nil, errors.New("worker request invalid")
	}
	r.Header.Set("Authorization", "Bearer "+c.token)
	r.Header.Set("X-Podcast-Version", "1")
	if body != nil {
		r.Header.Set("Content-Type", "application/octet-stream")
		r.Header.Set("X-Podcast-Language", language)
		r.ContentLength = length
	}
	resp, e := c.http.Do(r)
	if e != nil {
		return nil, errors.New("private transcription worker unavailable")
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, errors.New("private transcription worker rejected request")
	}
	b, e := io.ReadAll(io.LimitReader(resp.Body, podcastMaxResponseBytes+1))
	if e != nil || len(b) > podcastMaxResponseBytes {
		return nil, errors.New("worker response exceeds limit")
	}
	return b, nil
}
func (c *podcastRemote) ready(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	b, e := c.request(ctx, "GET", "/internal/podcast/ready", nil, "", 0)
	if e != nil {
		return e
	}
	var v struct {
		Version  int  `json:"version"`
		Ready    bool `json:"ready"`
		Capacity int  `json:"capacity"`
	}
	if json.Unmarshal(b, &v) != nil || v.Version != 1 || !v.Ready || v.Capacity != 1 {
		return errors.New("transcription worker not ready")
	}
	return nil
}
func (c *podcastRemote) transcribe(ctx context.Context, path, language string) ([]podcastSegment, error) {
	if language != "de" && language != "ru" {
		return nil, errors.New("unsupported language")
	}
	limits, e := configuredPodcastLimits()
	if e != nil {
		return nil, e
	}
	f, e := os.Open(path)
	if e != nil {
		return nil, errors.New("audio unavailable")
	}
	defer f.Close()
	st, e := f.Stat()
	if e != nil || !st.Mode().IsRegular() || st.Size() <= 0 || st.Size() > limits.bytes {
		return nil, errors.New("audio size invalid")
	}
	b, e := c.request(ctx, "POST", "/internal/podcast/transcribe", f, language, st.Size())
	if e != nil {
		return nil, e
	}
	var v struct {
		Version  int              `json:"version"`
		Segments []podcastSegment `json:"segments"`
	}
	if json.Unmarshal(b, &v) != nil || v.Version != 1 || len(v.Segments) == 0 || len(v.Segments) > podcastMaxSegments {
		return nil, errors.New("invalid worker transcript")
	}
	total := 0
	previous := 0.0
	for i := range v.Segments {
		s := &v.Segments[i]
		s.Translation = ""
		s.Text = strings.TrimSpace(s.Text)
		total += runeCount(s.Text)
		if s.Text == "" || math.IsNaN(s.Start) || math.IsNaN(s.End) || math.IsInf(s.Start, 0) || math.IsInf(s.End, 0) || s.Start < previous || s.End <= s.Start || s.End > float64(limits.duration) || total > podcastMaxCharacters || runeCount(s.Text) > podcastMaxSegmentCharacters {
			return nil, errors.New("invalid worker transcript")
		}
		previous = s.End
	}
	return v.Segments, nil
}
