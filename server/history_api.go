package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"path/filepath"
	"strings"
	"time"
)

// Account history never falls back to the shared legacy store or provider key.
func (cfg *serverConfig) handleHistory(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	user, ok := cfg.provider.owner(w, r)
	if !ok {
		return
	}
	id := strings.TrimPrefix(r.URL.Path, "/v1/history/")
	list := r.URL.Path == "/v1/history"
	if !list && (id == "" || len(id) > 128 || strings.ContainsAny(id, "/\\")) {
		writeError(w, 404, "history record not found")
		return
	}
	if (list && r.Method != http.MethodGet) || (!list && r.Method != http.MethodPatch && r.Method != http.MethodDelete) {
		writeError(w, 405, "method not allowed")
		return
	}
	var input struct {
		Favorite *bool `json:"favorite"`
	}
	if r.Method == http.MethodPatch {
		// Decode outside any store/provider lock. Production also has ReadTimeout;
		// set an explicit body deadline for alternate HTTP server embeddings.
		controller := http.NewResponseController(w)
		_ = controller.SetReadDeadline(time.Now().Add(10 * time.Second))
		defer controller.SetReadDeadline(time.Time{})
		defer r.Body.Close()
		d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024))
		d.DisallowUnknownFields()
		if d.Decode(&input) != nil || input.Favorite == nil || d.Decode(new(any)) != io.EOF {
			writeError(w, 400, "expected favorite boolean only")
			return
		}
		if r.Context().Err() != nil {
			writeError(w, 408, "request canceled")
			return
		}
	}
	history, err := openHistory(filepath.Join(filepath.Dir(cfg.historyPath), "users", sessionHash(user)+".json"))
	if err != nil {
		writeError(w, 503, "history unavailable")
		return
	}
	if list {
		items, err := history.list()
		if err != nil {
			writeError(w, 503, "history unavailable")
			return
		}
		writeJSON(w, 200, map[string]any{"items": items})
		return
	}
	if r.Method == http.MethodDelete {
		err := history.delete(id)
		if errors.Is(err, errHistoryNotFound) {
			writeError(w, 404, "history record not found")
			return
		}
		if err != nil {
			writeError(w, 503, "could not save history")
			return
		}
		w.WriteHeader(http.StatusNoContent)
		return
	}
	record, err := history.favorite(id, *input.Favorite)
	if errors.Is(err, errHistoryNotFound) {
		writeError(w, 404, "history record not found")
		return
	}
	if err != nil {
		writeError(w, 503, "could not save history")
		return
	}
	writeJSON(w, 200, record)
}
