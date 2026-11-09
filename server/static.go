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
	case "/app.mjs":
		name = "app.mjs"
	case "/core.mjs":
		name = "core.mjs"
	case "/styles.css":
		name = "styles.css"
	case "/favicon.svg":
		name = "favicon.svg"
	case "/apple-sign-in-de.png":
		name = "apple-sign-in-de.png"
	default:
		http.NotFound(w, r)
		return
	}
	data, e := os.ReadFile(filepath.Join(getenv("WEB_ASSET_DIR", "../web"), name))
	if e != nil {
		writeError(w, 503, "web assets unavailable")
		return
	}
	switch filepath.Ext(name) {
	case ".mjs":
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
	if r.Method == "GET" {
		_, _ = w.Write(data)
	}
}
