package main

import (
	"encoding/json"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func dictationTestAPI(t *testing.T) (*serverConfig, func(string, string, string) *httptest.ResponseRecorder) {
	t.Helper()
	dir := t.TempDir()
	cfg := &serverConfig{authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json")}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	token, _, err := cfg.auth.store.create("lifecycle-owner", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	return cfg, func(method, path, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, "/v1/learning/dictations"+path, strings.NewReader(body))
		r.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
}
func TestDictationCheckRequiresCurrentRevision(t *testing.T) {
	_, call := dictationTestAPI(t)
	call("POST", "", `{"id":"one","title":"Title","text":"Hallo Welt.","language":"de"}`)
	call("PUT", "/one", `{"mode":"whole","draft":"Hallo","revision":0}`)
	if w := call("POST", "/one/check", `{"revision":0}`); w.Code != 409 {
		t.Fatalf("stale check: %d", w.Code)
	}
	if w := call("POST", "/one/check", `{"revision":1}`); w.Code != 200 {
		t.Fatalf("current check: %d", w.Code)
	}
}

func TestDictationAcknowledgementRetry(t *testing.T) {
	_, call := dictationTestAPI(t)
	call("POST", "", `{"id":"one","title":"Title","text":"Hallo Welt.","language":"de"}`)
	body := `{"mode":"whole","step":0,"replays":0,"draft":"Hallo","revision":0,"mutation_id":"save-one"}`
	first := call("PUT", "/one", body)
	if first.Code != 200 {
		t.Fatalf("first save: %d %s", first.Code, first.Body.String())
	}
	retry := call("PUT", "/one", body)
	if retry.Code != 200 || retry.Body.String() != first.Body.String() {
		t.Fatalf("lost acknowledgment retry: %d %s", retry.Code, retry.Body.String())
	}
	// The same operation identifier cannot be reused with different content.
	if w := call("PUT", "/one", strings.Replace(body, "Hallo", "changed", 1)); w.Code != 409 {
		t.Fatalf("ID collision: %d", w.Code)
	}
	// Different device cannot overwrite a newer revision.
	if w := call("PUT", "/one", strings.Replace(body, "save-one", "device-two", 1)); w.Code != 409 {
		t.Fatalf("stale device: %d", w.Code)
	}
}
func TestDictationAttemptsAndDeleteTombstone(t *testing.T) {
	_, call := dictationTestAPI(t)
	create := `{"id":"one","title":"Title","text":"Hallo Welt.","language":"de"}`
	call("POST", "", create)
	call("PUT", "/one", `{"mode":"whole","step":0,"draft":"unfinished","revision":0}`)
	for i := 0; i < 2; i++ {
		w := call("POST", "/one/attempts", `{"id":"two"}`)
		if w.Code != 200 {
			t.Fatalf("attempt: %d %s", w.Code, w.Body.String())
		}
	}
	var value map[string]any
	json.Unmarshal(call("GET", "/two", "").Body.Bytes(), &value)
	if value["draft"] != "" || value["text_id"] != "one" {
		t.Fatalf("fresh related attempt: %#v", value)
	}
	if !strings.Contains(call("GET", "/one", "").Body.String(), "unfinished") {
		t.Fatal("old draft lost")
	}
	for i := 0; i < 2; i++ {
		if w := call("DELETE", "/two", `{"revision":0}`); w.Code != 200 {
			t.Fatalf("delete retry: %d", w.Code)
		}
	}
	if w := call("GET", "/two", ""); w.Code != 404 {
		t.Fatal("deleted attempt still readable")
	}
	if w := call("POST", "/one/attempts", `{"id":"two"}`); w.Code != 409 {
		t.Fatal("delayed retry resurrected deleted attempt")
	}
	if w := call("DELETE", "/one", `{"revision":0}`); w.Code != 409 {
		t.Fatal("stale delete discarded another device's draft")
	}
	if w := call("DELETE", "/one", `{"revision":1}`); w.Code != 200 {
		t.Fatal("delete", w.Code)
	}
	if w := call("POST", "", create); w.Code != 409 {
		t.Fatal("delayed create resurrected deleted text")
	}
}
