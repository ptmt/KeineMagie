package main

import (
	"net/http"
	"os"
	"path/filepath"
)

// Explicit public allowlist, never a general directory file server. Docker copies
// exactly these runtime files; source, tests and credentials are never served.
func publicWeb(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self'; object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Cache-Control", "no-store")
	if r.Method != "GET" && r.Method != "HEAD" {
		writeError(w, 405, "method not allowed")
		return
	}
	name := ""
	switch r.URL.Path {
	case "/", "/index.html":
		name = "index.html"
	case "/episode.mjs", "/episode-view.mjs", "/episode-i18n.mjs", "/episode.css":
		name = r.URL.Path[1:]
	case "/translator-followup.mjs", "/translator-followup.css":
		name = r.URL.Path[1:]
	case "/bootstrap.js":
		name = "bootstrap.js"
	case "/app.mjs":
		name = "app.mjs"
	case "/i18n.mjs":
		name = "i18n.mjs"
	case "/core.mjs":
		name = "core.mjs"
	case "/styles.css":
		name = "styles.css"
	case "/favicon.svg":
		name = "favicon.svg"
	case "/apple-sign-in-de.png", "/apple-sign-in-en.png", "/apple-sign-in-ru.png", "/apple-sign-in-es.png", "/apple-sign-in-fr.png":
		name = r.URL.Path[1:]
	default:
		if isPodcastEpisodePath(r.URL.Path) {
			name = "index.html"
		} else {
			http.NotFound(w, r)
			return
		}
	}
	data, e := os.ReadFile(filepath.Join(getenv("WEB_ASSET_DIR", "../web"), name))
	if e != nil {
		writeError(w, 503, "web assets unavailable")
		return
	}
	switch filepath.Ext(name) {
	case ".mjs", ".js":
		w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
	case ".css":
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
	case ".html":
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
	case ".png":
		w.Header().Set("Content-Type", "image/png")
	case ".svg":
		w.Header().Set("Content-Type", "image/svg+xml")
	}
	if name == "bootstrap.js" {
		w.Header().Set("Cache-Control", "public, max-age=0, must-revalidate")
	}
	if r.Method == "GET" {
		_, _ = w.Write(data)
	}
}
