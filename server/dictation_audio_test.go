package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDictationAudioPrivateRange(t *testing.T) {
	dir := t.TempDir()
	cfg := &serverConfig{authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json")}
	h, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	token, s, _ := cfg.auth.store.create("audio-owner", time.Now())
	other, _, _ := cfg.auth.store.create("other", time.Now())
	cfg.dictationTransaction(s.UserID, true, func(d *dictationData) error {
		d.Items = append(d.Items, dictationRecord{ID: "audio", Text: "Hallo.", Plan: dictationPlan("Hallo.")})
		return nil
	})
	path := dictationAssetPath(cfg.dictationRoot(s.UserID), "audio", 0)
	os.MkdirAll(filepath.Dir(path), 0700)
	// Tiny PCM fixture tests HTTP only; never claimed as synthesized speech.
	b := make([]byte, 48)
	copy(b, "RIFF")
	binary.LittleEndian.PutUint32(b[4:], 40)
	copy(b[8:], "WAVEfmt ")
	binary.LittleEndian.PutUint32(b[16:], 16)
	binary.LittleEndian.PutUint16(b[20:], 1)
	binary.LittleEndian.PutUint16(b[22:], 1)
	binary.LittleEndian.PutUint32(b[24:], 22050)
	binary.LittleEndian.PutUint32(b[28:], 44100)
	binary.LittleEndian.PutUint16(b[32:], 2)
	binary.LittleEndian.PutUint16(b[34:], 16)
	copy(b[36:], "data")
	binary.LittleEndian.PutUint32(b[40:], 4)
	os.WriteFile(path, b, 0600)
	call := func(auth, method string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, "/v1/learning/dictations/audio/audio/0", strings.NewReader("{}"))
		r.Header.Set("Authorization", "Bearer "+auth)
		r.Header.Set("Range", "bytes=0-11")
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	if w := call(token, "GET"); w.Code != 206 || !bytes.Equal(w.Body.Bytes(), b[:12]) || w.Header().Get("Cache-Control") != "no-store" {
		t.Fatal(w.Code, w.Header())
	}
	for _, tc := range []struct {
		value  string
		code   int
		length int
	}{{"bytes=-4", 206, 4}, {"bytes=44-", 206, 4}, {"bytes=999-", 416, 0}, {"bytes=12-0", 416, 0}} {
		r := httptest.NewRequest("GET", "/v1/learning/dictations/audio/audio/0", nil)
		r.Header.Set("Authorization", "Bearer "+token)
		r.Header.Set("Range", tc.value)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != tc.code || tc.length > 0 && w.Body.Len() != tc.length {
			t.Fatalf("range %s: %d %d", tc.value, w.Code, w.Body.Len())
		}
	}
	if w := call(other, "GET"); w.Code != 404 {
		t.Fatal("owner leak", w.Code)
	}
	if w := call("", "GET"); w.Code != 401 {
		t.Fatal("guest", w.Code)
	}
	if w := call(token, "POST"); w.Code != 200 {
		t.Fatal("idempotent existing asset", w.Code)
	}
	cfg.dictationTransaction(s.UserID, false, func(d *dictationData) error {
		if len(dictationFind(d, "audio").Ready) != 1 {
			t.Error("crash-resume ready metadata not repaired")
		}
		return nil
	})
	cfg.auth.store.lock.locked(func() error {
		d, e := cfg.auth.store.read()
		if e != nil {
			return e
		}
		delete(d.Sessions, sessionHash(token))
		return cfg.auth.store.write(d)
	})
	if w := call(token, "GET"); w.Code != 401 {
		t.Fatal("revoked", w.Code)
	}
}
func TestDictationProductionDoesNotUseLegacyWorker(t *testing.T) {
	t.Setenv("DICTATION_TTS_PROVIDER", "")
	p := filepath.Join(t.TempDir(), "engine")
	os.WriteFile(p, []byte("#!/bin/sh\nexit 0\n"), 0700)
	model := filepath.Join(t.TempDir(), "voice")
	os.WriteFile(model, []byte("fixture"), 0600)
	os.WriteFile(model+".json", []byte("{}"), 0600)
	t.Setenv("DICTATION_MODEL", model)
	t.Setenv("DICTATION_TTS_EXECUTABLE", p)
	if dictationTTSAvailable() {
		t.Fatal("legacy engine advertised as production speech")
	}
}

func TestDictationSynthesisCancellation(t *testing.T) {
	script := filepath.Join(t.TempDir(), "engine")
	os.WriteFile(script, []byte("#!/bin/sh\nsleep 30\n"), 0700)
	t.Setenv("DICTATION_TTS_EXECUTABLE", script)
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	start := time.Now()
	if _, e := dictationLegacySynthesize(ctx, "Hallo"); e == nil {
		t.Fatal("cancellation ignored")
	}
	if time.Since(start) > 2*time.Second {
		t.Fatal("child process not canceled")
	}
}
