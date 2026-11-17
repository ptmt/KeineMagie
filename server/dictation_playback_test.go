package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDictationPlaybackPolicy(t *testing.T) {
	t.Setenv("WEB_ORIGIN", "https://example.com")
	dir := t.TempDir()
	cfg := &serverConfig{authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json")}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	token, s, _ := cfg.auth.store.create("playback-owner", time.Now())
	browser, _ := cfg.auth.store.createBrowser(token, s.UserID, time.Now())
	call := func(method, path, body string, want int) string {
		t.Helper()
		r := httptest.NewRequest(method, "/v1/learning/dictations"+path, strings.NewReader(body))
		r.AddCookie(&http.Cookie{Name: browserCookie, Value: browser})
		r.Header.Set("Origin", "https://example.com")
		r.Header.Set("X-CSRF-Token", browserCSRF(browser))
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != want {
			t.Fatalf("%s %s: %d want %d: %s", method, path, w.Code, want, w.Body)
		}
		return w.Body.String()
	}
	create := func(id, version string, want int) {
		call("POST", "", fmt.Sprintf(`{"id":%q,"title":"Test","text":"Hallo. Morgen!","language":"de"%s}`, id, version), want)
	}
	for _, v := range []string{`0`, `2`, `-1`, `"1"`, `null`, `1.0`, `1e0`, `true`} {
		create("bad", `,"playback_policy_version":`+v, 400)
	}
	create("legacy", "", 200)
	call("POST", "/legacy/playback", `{"id":"legacy","client":"tab","action":"start"}`, 409)
	create("one", `,"playback_policy_version":1`, 200)
	create("one", "", 409)
	path := dictationAssetPath(cfg.dictationRoot(s.UserID), "one", 0)
	os.MkdirAll(filepath.Dir(path), 0700)
	os.WriteFile(path, []byte("synthetic"), 0600)
	req := func(id, client, action string, fence int, offset float64) string {
		return fmt.Sprintf(`{"id":%q,"client":%q,"action":%q,"step":0,"fence":%d,"offset":%g}`, id, client, action, fence, offset)
	}
	var ledger dictationPlayback
	decode := func(body string) {
		t.Helper()
		if e := json.Unmarshal([]byte(body), &ledger); e != nil {
			t.Fatal(e)
		}
	}
	decode(call("POST", "/one/playback", req("listen1", "tab1", "start", 0, 0), 200))
	if ledger.WholeStarts != 1 || ledger.Revision != 1 {
		t.Fatal(ledger)
	}
	fence := ledger.Active.Fence
	decode(call("POST", "/one/playback", req("listen1", "tab1", "start", 0, 0), 200))
	if ledger.WholeStarts != 1 {
		t.Fatal(ledger)
	}
	call("POST", "/one/playback", req("listen2", "tab2", "start", 0, 0), 409)
	call("POST", "/one/playback", req("listen1", "tab2", "resume", fence, 0), 409)
	decode(call("POST", "/one/playback", req("listen1", "tab1", "progress", fence, 1.5), 200))
	fence = ledger.Active.Fence
	call("PUT", "/one", `{"mode":"sentences","step":1,"draft":"Hallo","revision":0}`, 200)
	call("POST", "/one/playback", req("listen1", "tab1", "release", fence, 1.5), 200)
	decode(call("POST", "/one/playback", req("listen1", "tab2", "resume", fence, 0), 200))
	if ledger.Active.Offset != 1.5 || ledger.Active.Fence <= fence {
		t.Fatal(ledger)
	}
	call("POST", "/one/playback", req("listen1", "tab1", "ended", fence, 2), 409)
	fence = ledger.Active.Fence
	call("POST", "/one/playback", req("listen1", "tab2", "ended", fence, 2), 200)
	call("POST", "/one/playback", req("listen1", "tab2", "ended", fence, 2), 200)
	for i := 2; i <= 4; i++ {
		id := fmt.Sprintf("listen%d", i)
		decode(call("POST", "/one/playback", req(id, "tab2", "start", 0, 0), 200))
		call("POST", "/one/playback", req(id, "tab2", "ended", ledger.Active.Fence, 2), 200)
	}
	h, err = newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	call("POST", "/one/playback", req("fifth", "tab2", "start", 0, 0), 409)
	body := call("GET", "/one", "", 200)
	if !strings.Contains(body, `"whole_starts":4`) || !strings.Contains(body, `"draft":"Hallo"`) {
		t.Fatal(body)
	}
	call("POST", "/one/attempts", `{"id":"new","playback_policy_version":1}`, 200)
	body = call("GET", "/new", "", 200)
	if !strings.Contains(body, `"whole_starts":0`) {
		t.Fatal(body)
	}
	other, ss, _ := cfg.auth.store.create("other", time.Now())
	browser, _ = cfg.auth.store.createBrowser(other, ss.UserID, time.Now())
	call("POST", "/one/playback", req("steal", "tab2", "start", 0, 0), 404)
	call("GET", "/one/audio/0", "", 404)
}
