package main

import (
	"bytes"
	"context"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"strings"
	"time"
)

// Images use the exact audio/feed DNS-pinned transport and redirect policy.
// Only owner-resolved stored subscriptions can select a destination, never a
// client URL. DecodeConfig bounds dimensions without allocating decoded pixels.
func (p *podcastService) handleArtwork(w http.ResponseWriter, r *http.Request, sub podcastSubscription) {
	if r.Method != "GET" {
		writeError(w, 405, "method not allowed")
		return
	}
	u, err := podcastURL(sub.ArtworkURL)
	if err != nil {
		writeError(w, 404, "artwork unavailable")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()
	f := podcastFetcher{}
	if p.sourceFetcher != nil {
		f = *p.sourceFetcher
	}
	client := f.client()
	defer client.CloseIdleConnections()
	resp, err := podcastDocument(ctx, u, client)
	if err != nil {
		writeError(w, 502, "artwork unavailable")
		return
	}
	defer resp.Body.Close()
	mime := strings.ToLower(strings.TrimSpace(strings.Split(resp.Header.Get("Content-Type"), ";")[0]))
	if (mime != "image/jpeg" && mime != "image/png") || resp.ContentLength > 2<<20 {
		writeError(w, 502, "unsupported artwork")
		return
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, (2<<20)+1))
	if err != nil || len(b) > 2<<20 {
		writeError(w, 502, "artwork exceeds limit")
		return
	}
	cfg, format, err := image.DecodeConfig(bytes.NewReader(b))
	if err != nil || cfg.Width <= 0 || cfg.Height <= 0 || cfg.Width > 4096 || cfg.Height > 4096 || cfg.Width*cfg.Height > 16_000_000 || (format == "png" && mime != "image/png") || (format == "jpeg" && mime != "image/jpeg") {
		writeError(w, 502, "invalid artwork")
		return
	}
	w.Header().Set("Content-Type", mime)
	w.Header().Set("Cache-Control", "private, no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(200)
	w.Write(b)
}
