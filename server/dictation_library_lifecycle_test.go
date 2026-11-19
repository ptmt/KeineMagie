package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDictationLibraryLifecycleTransitions(t *testing.T) {
	root := t.TempDir()
	cfg := &serverConfig{authPath: filepath.Join(root, "auth.json"), historyPath: filepath.Join(root, "history.json")}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	token, s, _ := cfg.auth.store.create("transitions", time.Now())
	call := func(method, path, body string, want int, canceled bool) string {
		t.Helper()
		r := httptest.NewRequest(method, "/v1/learning/dictations"+path, strings.NewReader(body))
		r.Header.Set("Authorization", "Bearer "+token)
		if canceled {
			ctx, cancel := context.WithCancel(r.Context())
			cancel()
			r = r.WithContext(ctx)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != want {
			t.Fatalf("%s %s: %d want %d: %s", method, path, w.Code, want, w.Body.String())
		}
		return w.Body.String()
	}
	stage := func(id, want string) {
		t.Helper()
		path := filepath.Join(cfg.dictationRoot(s.UserID), "history.json")
		before, _ := os.ReadFile(path)
		var list struct {
			Items []dictationLibraryItem `json:"items"`
		}
		json.Unmarshal([]byte(call("GET", "", "", 200, false)), &list)
		after, _ := os.ReadFile(path)
		if string(before) != string(after) {
			t.Fatal("list wrote state")
		}
		for _, v := range list.Items {
			if v.ID == id {
				if v.LifecycleStage != want {
					t.Fatalf("%s = %s want %s", id, v.LifecycleStage, want)
				}
				return
			}
		}
		if want != "absent" {
			t.Fatalf("missing %s", id)
		}
	}
	call("POST", "", `{"id":"one","title":"One","text":"Hallo. Morgen!","language":"de","playback_policy_version":1}`, 200, false)
	stage("one", "added")
	call("GET", "/one", "", 200, false)
	stage("one", "added")
	start := `{"id":"listen","client":"browser","action":"start","step":0}`
	call("POST", "/one/playback", start, 404, false)
	stage("one", "added")
	// Preparation is durable only after publication; a file alone is not ready.
	path := dictationAssetPath(cfg.dictationRoot(s.UserID), "one", 0)
	os.MkdirAll(filepath.Dir(path), 0700)
	os.WriteFile(path, []byte("synthetic"), 0600)
	call("POST", "/one/audio/0", `{}`, 200, false)
	stage("one", "ready")
	call("POST", "/one/playback", start, 503, true)
	stage("one", "ready")
	var ledger dictationPlayback
	json.Unmarshal([]byte(call("POST", "/one/playback", start, 200, false)), &ledger)
	if ledger.WholeStarts != 1 || len(ledger.Listens) != 1 {
		t.Fatal(ledger)
	}
	stage("one", "started")
	// Canceling an admitted playback does not erase that real start.
	call("POST", "/one/playback", fmt.Sprintf(`{"id":"listen","client":"browser","action":"cancel","step":0,"fence":%d}`, ledger.Active.Fence), 200, false)
	stage("one", "started")
	call("POST", "/one/attempts", `{"id":"new","playback_policy_version":1}`, 200, false)
	stage("new", "ready")
	// Remote mode changes are not practice and use the new mode's assets.
	call("PUT", "/new", `{"revision":0,"mode":"sentences","step":1,"draft":" "}`, 200, false)
	stage("new", "added")
	var record dictationRecord
	json.Unmarshal([]byte(call("GET", "/new", "", 200, false)), &record)
	for _, segment := range record.Plan {
		p := dictationAssetPath(cfg.dictationRoot(s.UserID), "new", segment.Asset)
		os.WriteFile(p, []byte("synthetic"), 0600)
		call("POST", fmt.Sprintf("/new/audio/%d", segment.Asset), `{}`, 200, false)
	}
	stage("new", "ready")
	// Segment admission counts even though the whole counter remains zero.
	json.Unmarshal([]byte(call("POST", "/new/playback", `{"id":"segment","client":"browser","action":"start","step":1}`, 200, false)), &ledger)
	if ledger.WholeStarts != 0 || len(ledger.Listens) != 1 {
		t.Fatal(ledger)
	}
	stage("new", "started")
	call("PUT", "/new", `{"revision":1,"mode":"sentences","step":1,"draft":"Incorrect answer"}`, 200, false)
	call("POST", "/new/check", `{"revision":2}`, 200, false)
	stage("new", "completed")
	// Reload handler/store, not in-memory projection.
	h, err = newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	stage("new", "completed")
	stage("one", "started")
	originalToken := token
	token, _, _ = cfg.auth.store.create("another-owner", time.Now())
	call("GET", "/new", "", 404, false)
	stage("new", "absent")
	token = originalToken
	call("DELETE", "/new", `{"revision":3}`, 200, false)
	stage("new", "absent")
	stage("one", "started")
}

func TestDictationLibraryLifecycle(t *testing.T) {
	cfg := &serverConfig{authPath: filepath.Join(t.TempDir(), "auth.json"), historyPath: filepath.Join(t.TempDir(), "history.json")}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	token, s, _ := cfg.auth.store.create("lifecycle", time.Now())
	plan := dictationPlan("Heute scheint die Sonne. Wir gehen hinaus.")
	allAssets := []int{0}
	for _, segment := range plan {
		if segment.Asset != 0 {
			allAssets = append(allAssets, segment.Asset)
		}
	}
	cases := []struct {
		name   string
		edit   func(*dictationRecord)
		assets []int
		want   string
	}{
		{"added", nil, nil, "added"},
		{"ready", func(v *dictationRecord) { v.Ready = []int{0} }, []int{0}, "ready"},
		{"typed", func(v *dictationRecord) { v.Draft = " private answer " }, nil, "started"},
		{"checked_without_audio", func(v *dictationRecord) { v.Checked = true; v.Draft = "wrong answer" }, nil, "completed"},
		{"whitespace", func(v *dictationRecord) { v.Draft = " \n\t" }, nil, "added"},
		{"opened_revealed", func(v *dictationRecord) { v.Revision = 3; v.Assisted = true; v.Step = 1 }, nil, "added"},
		{"missing_file", func(v *dictationRecord) { v.Ready = []int{0} }, nil, "added"},
		{"unpublished_file", nil, []int{0}, "added"},
		{"mode_changed", func(v *dictationRecord) { v.Mode = "sentences"; v.Ready = []int{0} }, []int{0}, "added"},
		{"all_passages", func(v *dictationRecord) { v.Mode = "sentences"; v.Ready = allAssets }, allAssets, "ready"},
		{"passages_without_final_whole", func(v *dictationRecord) { v.Mode = "sentences"; v.Ready = allAssets[1:] }, allAssets[1:], "added"},
		{"partial_preparation", func(v *dictationRecord) { v.Mode = "sentences"; v.Ready = []int{plan[1].Asset} }, []int{plan[1].Asset}, "added"},
		{"fresh_attempt_without_audio", nil, nil, "added"},
		{"legacy_replay", func(v *dictationRecord) { v.PlaybackPolicyVersion = 0; v.Replays = 1 }, nil, "started"},
		{"new_policy_legacy_counter", func(v *dictationRecord) { v.Replays = 4 }, nil, "added"},
		{"whole_start", func(v *dictationRecord) { v.Playback.WholeStarts = 1 }, nil, "started"},
		{"segment_start", func(v *dictationRecord) {
			v.Playback.Listens = []dictationListen{{ID: "start", Client: "client", Step: 1, Fence: 1}}
		}, nil, "started"},
		{"legacy_current_asset", func(v *dictationRecord) {
			v.PlaybackPolicyVersion = 0
			v.Mode = "sentences"
			v.Step = 1
			v.Ready = []int{plan[1].Asset}
		}, []int{plan[1].Asset}, "ready"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			v := dictationRecord{ID: tc.name, Title: tc.name, Text: "Heute scheint die Sonne. Wir gehen hinaus.", Mode: "whole", Plan: plan, PlaybackPolicyVersion: 1, Playback: dictationPlayback{Cursor: 1}}
			if tc.edit != nil {
				tc.edit(&v)
			}
			if err := cfg.dictationTransaction(s.UserID, true, func(d *dictationData) error { d.Items = []dictationRecord{v}; return nil }); err != nil {
				t.Fatal(err)
			}
			for _, asset := range tc.assets {
				p := dictationAssetPath(cfg.dictationRoot(s.UserID), v.ID, asset)
				os.MkdirAll(filepath.Dir(p), 0700)
				if err := os.WriteFile(p, []byte("existing audio"), 0600); err != nil {
					t.Fatal(err)
				}
			}
			r := httptest.NewRequest("GET", "/v1/learning/dictations", nil)
			r.Header.Set("Authorization", "Bearer "+token)
			w := httptest.NewRecorder()
			h.ServeHTTP(w, r)
			var body struct {
				Items []map[string]any `json:"items"`
			}
			if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
				t.Fatal(err)
			}
			if w.Code != 200 || len(body.Items) != 1 {
				t.Fatal(w.Code, w.Body.String())
			}
			if got := body.Items[0]["lifecycle_stage"]; got != tc.want {
				t.Fatalf("stage=%v want %s", got, tc.want)
			}
			if body.Items[0]["draft"] != "" || body.Items[0]["text"] != nil {
				t.Fatal("private content exposed")
			}
		})
	}
}
