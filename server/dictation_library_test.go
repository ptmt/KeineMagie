package main

import (
	"encoding/binary"
	"encoding/json"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDictationLibraryMetadata(t *testing.T) {
	cfg := &serverConfig{authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json")}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	token, session, _ := cfg.auth.store.create("library-owner", time.Now())
	text := "Über Café Cafe\u0301 Straße 123 geht’s."
	err = cfg.dictationTransaction(session.UserID, true, func(d *dictationData) error {
		d.Items = []dictationRecord{{ID: "one", Title: "Übung", Text: text, Draft: "private answer", Plan: dictationPlan(text), Ready: []int{0}}}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	call := func(auth string) *httptest.ResponseRecorder {
		r := httptest.NewRequest("GET", "/v1/learning/dictations", nil)
		if auth != "" {
			r.Header.Set("Authorization", "Bearer "+auth)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	read := func() map[string]any {
		w := call(token)
		if w.Code != 200 {
			t.Fatal(w.Code, w.Body.String())
		}
		var body struct {
			Items []map[string]any `json:"items"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		if strings.Contains(w.Body.String(), "private answer") || strings.Contains(w.Body.String(), "Straße") {
			t.Fatal("list leaked original/draft")
		}
		return body.Items[0]
	}
	item := read()
	if item["word_count"] != float64(6) {
		t.Fatalf("word count: %#v", item)
	}
	if _, ok := item["audio_duration_seconds"]; ok {
		t.Fatal("missing audio invented duration")
	}
	path := dictationAssetPath(cfg.dictationRoot(session.UserID), "one", 0)
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	// Real canonical PCM header metadata + sparse payload, no provider request.
	wav := make([]byte, 44)
	copy(wav, "RIFF")
	binary.LittleEndian.PutUint32(wav[4:], 36+48000*95)
	copy(wav[8:], "WAVEfmt ")
	binary.LittleEndian.PutUint32(wav[16:], 16)
	binary.LittleEndian.PutUint16(wav[20:], 1)
	binary.LittleEndian.PutUint16(wav[22:], 1)
	binary.LittleEndian.PutUint32(wav[24:], 24000)
	binary.LittleEndian.PutUint32(wav[28:], 48000)
	binary.LittleEndian.PutUint16(wav[32:], 2)
	binary.LittleEndian.PutUint16(wav[34:], 16)
	copy(wav[36:], "data")
	binary.LittleEndian.PutUint32(wav[40:], 48000*95)
	write := func() {
		if err := os.WriteFile(path, wav, 0600); err != nil {
			t.Fatal(err)
		}
		if err := os.Truncate(path, 44+48000*95); err != nil {
			t.Fatal(err)
		}
	}
	write()
	if got := read()["audio_duration_seconds"]; got != float64(95) {
		t.Fatalf("actual WAV duration: %v", got)
	}
	// Segments alone never masquerade as the complete recording.
	if err := os.Rename(path, dictationAssetPath(cfg.dictationRoot(session.UserID), "one", 1)); err != nil {
		t.Fatal(err)
	}
	if _, ok := read()["audio_duration_seconds"]; ok {
		t.Fatal("segment-only duration")
	}
	write()
	if err := os.Truncate(path, 45); err != nil {
		t.Fatal(err)
	}
	if _, ok := read()["audio_duration_seconds"]; ok {
		t.Fatal("truncated audio duration")
	}
	binary.LittleEndian.PutUint32(wav[28:], 0)
	write()
	if _, ok := read()["audio_duration_seconds"]; ok {
		t.Fatal("invalid byte rate")
	}
	if w := call(""); w.Code != 401 {
		t.Fatal("guest", w.Code)
	}
	other, _, _ := cfg.auth.store.create("library-other", time.Now())
	if w := call(other); w.Code != 200 || strings.Contains(w.Body.String(), "word_count") || strings.Contains(w.Body.String(), "Übung") {
		t.Fatal("owner leak", w.Body.String())
	}
}
