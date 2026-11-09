package main

import "net/http"

// Native bundle audience is not an Apple web Services ID. Do not manufacture a
// website callback or expose bearer tokens to browser JavaScript as a shortcut.
func webRegistrationGate(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if r.Method != "GET" {
		writeError(w, 405, "method not allowed")
		return
	}
	switch r.URL.Path {
	case "/v1/web/config":
		writeJSON(w, 200, map[string]any{"apple_available": false, "apple_reason": "Apple web sign-in requires a separately registered Services ID and authorized HTTPS callback. Browser cookie/CSRF authorization is not configured; native Apple sessions cannot be reused in browser storage.", "chatgpt_connect_available": false})
	case "/v1/web/session":
		writeError(w, 401, "browser session unavailable: Apple web registration required")
	default:
		writeError(w, 503, "Apple web Services ID and HTTPS callback registration required")
	}
}
