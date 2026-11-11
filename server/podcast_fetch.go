package main

import (
	"context"
	"crypto/tls"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

// Credential-free public source URLs only. Permit only bounded public publisher
// version/tracking parameters, never arbitrary signed/private capabilities.
func podcastPublicQuery(raw string) bool {
	if raw == "" {
		return true
	}
	if len(raw) > 512 {
		return false
	}
	values, err := url.ParseQuery(raw)
	if err != nil || len(values) == 0 || len(values) > 3 {
		return false
	}
	for key, items := range values {
		if len(items) != 1 || items[0] == "" || len(items[0]) > 64 {
			return false
		}
		for _, c := range items[0] {
			switch key {
			case "v", "awEpisodeId":
				if c < '0' || c > '9' {
					return false
				}
			case "awCollectionId":
				if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-') {
					return false
				}
			default:
				return false
			}
		}
	}
	return true
}
func podcastURL(raw string) (*url.URL, error) {
	if len(raw) > 2048 {
		return nil, errors.New("URL too long")
	}
	u, e := url.Parse(raw)
	if e != nil || (u.Scheme != "https" && u.Scheme != "http") || u.Hostname() == "" || u.User != nil || !podcastPublicQuery(u.RawQuery) || u.Fragment != "" || u.Opaque != "" {
		return nil, errors.New("public direct audio URL required (no credentials, query or fragment)")
	}
	if u.Port() != "" && !((u.Scheme == "https" && u.Port() == "443") || (u.Scheme == "http" && u.Port() == "80")) {
		return nil, errors.New("nonstandard ports are not supported")
	}
	if ip := net.ParseIP(u.Hostname()); ip != nil && !podcastPublicIP(ip) {
		return nil, errors.New("private destination denied")
	}
	return u, nil
}
func podcastPublicIP(ip net.IP) bool {
	if ip == nil || !ip.IsGlobalUnicast() || ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() || ip.IsUnspecified() {
		return false
	}
	// Deny special-use, CGNAT, documentation, multicast, transition/NAT64 and reserved ranges.
	for _, cidr := range []string{"0.0.0.0/8", "100.64.0.0/10", "192.0.0.0/24", "192.0.2.0/24", "192.88.99.0/24", "198.18.0.0/15", "198.51.100.0/24", "203.0.113.0/24", "224.0.0.0/4", "240.0.0.0/4", "::/96", "64:ff9b::/96", "64:ff9b:1::/48", "100::/64", "2001::/23", "2002::/16", "3fff::/20"} {
		_, n, _ := net.ParseCIDR(cidr)
		if n.Contains(ip) {
			return false
		}
	}
	// IPv6 global unicast only; excludes future/special allocations.
	if ip.To4() == nil {
		_, n, _ := net.ParseCIDR("2000::/3")
		return n.Contains(ip)
	}
	return true
}

type podcastFetcher struct {
	lookup func(context.Context, string) ([]net.IPAddr, error)
	// Tests may redirect validated public-IP dials to an isolated HTTP fixture.
	// Nil always uses the real dialer; no production private-network bypass.
	dial func(context.Context, string, string) (net.Conn, error)
}

func (f podcastFetcher) addresses(ctx context.Context, host string) ([]net.IPAddr, error) {
	lookup := f.lookup
	if lookup == nil {
		lookup = net.DefaultResolver.LookupIPAddr
	}
	ips, e := lookup(ctx, host)
	if e != nil || len(ips) == 0 {
		return nil, errors.New("DNS resolution failed")
	}
	for _, ip := range ips {
		if !podcastPublicIP(ip.IP) {
			return nil, errors.New("private or special-use DNS destination denied")
		}
	}
	return ips, nil
}
func (f podcastFetcher) client() *http.Client {
	transport := &http.Transport{Proxy: nil, TLSClientConfig: &tls.Config{MinVersion: tls.VersionTLS12}, ResponseHeaderTimeout: 15 * time.Second, MaxResponseHeaderBytes: 32 << 10, DisableKeepAlives: true}
	transport.DialContext = func(ctx context.Context, network, address string) (net.Conn, error) {
		host, port, e := net.SplitHostPort(address)
		if e != nil {
			return nil, e
		}
		ips, e := f.addresses(ctx, host)
		if e != nil {
			return nil, e
		}
		// Dial the exact validated IP, not the hostname (DNS rebinding safe).
		dial := f.dial
		if dial == nil {
			dial = (&net.Dialer{Timeout: 10 * time.Second}).DialContext
		}
		return dial(ctx, network, net.JoinHostPort(ips[0].IP.String(), port))
	}
	return &http.Client{Transport: transport, Timeout: 10 * time.Minute, CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) >= 4 {
			return errors.New("redirect limit exceeded")
		}
		_, e := podcastURL(req.URL.String())
		return e
	}}
}
func (f podcastFetcher) fetch(ctx context.Context, raw, dest string) error {
	u, e := podcastURL(raw)
	if e != nil {
		return e
	}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Minute)
	defer cancel()
	client := f.client()
	defer client.CloseIdleConnections()
	media, e := podcastResolveAudio(ctx, u, client)
	if e != nil {
		return e
	}
	return podcastFetchHTTP(ctx, media, dest, client)
}

// Explicit client seam permits offline fixture transports without any production
// localhost/private-IP bypass.
func podcastFetchHTTP(ctx context.Context, u *url.URL, dest string, client *http.Client) error {
	limits, e := configuredPodcastLimits()
	if e != nil {
		return e
	}
	req, e := http.NewRequestWithContext(ctx, "GET", u.String(), nil)
	if e != nil {
		return e
	}
	req.Header.Set("Accept", "audio/*, application/octet-stream")
	resp, e := client.Do(req)
	if e != nil {
		return errors.New("audio fetch failed (destination, redirect, DNS or network policy)")
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 || resp.ContentLength > limits.bytes {
		return errors.New("audio unavailable or exceeds configured size limit")
	}
	mime := strings.ToLower(strings.Split(resp.Header.Get("Content-Type"), ";")[0])
	if !strings.HasPrefix(mime, "audio/") && mime != "application/octet-stream" {
		return errors.New("response is not audio")
	}
	out, e := os.OpenFile(dest, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if e != nil {
		return e
	}
	defer out.Close()
	n, e := io.Copy(out, io.LimitReader(resp.Body, limits.bytes+1))
	if e != nil {
		return errors.New("audio download interrupted")
	}
	if n == 0 || n > limits.bytes {
		return errors.New("audio empty or exceeds configured size limit")
	}
	return out.Sync()
}
