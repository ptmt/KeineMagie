package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type playbackFixture struct {
	cfg                   *serverConfig
	h                     http.Handler
	owner, token, browser string
}

func newPlaybackFixture(t *testing.T) *playbackFixture {
	t.Helper()
	t.Setenv("WEB_ORIGIN", "https://example.com")
	dir := t.TempDir()
	cfg := &serverConfig{authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json")}
	h, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	token, s, e := cfg.auth.store.create("policy-security", time.Now())
	if e != nil {
		t.Fatal(e)
	}
	browser, e := cfg.auth.store.createBrowser(token, s.UserID, time.Now())
	if e != nil {
		t.Fatal(e)
	}
	return &playbackFixture{cfg, h, s.UserID, token, browser}
}
func (f *playbackFixture) call(method, path, body string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, "/v1/learning/dictations"+path, strings.NewReader(body))
	r.AddCookie(&http.Cookie{Name: browserCookie, Value: f.browser})
	r.Header.Set("Origin", "https://example.com")
	r.Header.Set("X-CSRF-Token", browserCSRF(f.browser))
	w := httptest.NewRecorder()
	f.h.ServeHTTP(w, r)
	return w
}
func (f *playbackFixture) seed(t *testing.T) {
	t.Helper()
	w := f.call("POST", "", `{"id":"one","title":"Fixture","language":"de","text":"Hallo. Morgen!","playback_policy_version":1}`)
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body)
	}
	e := f.cfg.dictationTransaction(f.owner, true, func(d *dictationData) error {
		v := dictationFind(d, "one")
		for _, s := range v.Plan {
			path := dictationAssetPath(f.cfg.dictationRoot(f.owner), "one", s.Asset)
			if e := os.MkdirAll(filepath.Dir(path), 0700); e != nil {
				return e
			}
			if e := os.WriteFile(path, []byte("synthetic transport only"), 0600); e != nil {
				return e
			}
			v.Ready = append(v.Ready, s.Asset)
		}
		d.Day = "2000-01-01"
		d.Generations = 120
		return nil
	})
	if e != nil {
		t.Fatal(e)
	}
}
func playbackBody(id, client, action string, step, fence int) string {
	return fmt.Sprintf(`{"id":%q,"client":%q,"action":%q,"step":%d,"fence":%d,"offset":2}`, id, client, action, step, fence)
}
func playbackDecode(t *testing.T, w *httptest.ResponseRecorder) dictationPlayback {
	t.Helper()
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body)
	}
	var p dictationPlayback
	if e := json.Unmarshal(w.Body.Bytes(), &p); e != nil {
		t.Fatal(e)
	}
	return p
}
func TestDictationPlaybackConcurrentLeaseAndBudgets(t *testing.T) {
	f := newPlaybackFixture(t)
	f.seed(t)
	var wg sync.WaitGroup
	codes := make(chan int, 12)
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			codes <- f.call("POST", "/one/playback", playbackBody(fmt.Sprint("r", i), fmt.Sprint("tab", i), "start", 0, 0)).Code
		}(i)
	}
	wg.Wait()
	close(codes)
	wins := 0
	for code := range codes {
		if code == 200 {
			wins++
		} else if code != 409 {
			t.Fatal(code)
		}
	}
	if wins != 1 {
		t.Fatal("admitted concurrent players", wins)
	}
	var p dictationPlayback
	f.cfg.dictationTransaction(f.owner, false, func(d *dictationData) error {
		v := dictationFind(d, "one")
		p = v.Playback
		if v.Revision != 0 || d.Generations != 120 || d.Day != "2000-01-01" {
			t.Error("playback altered draft/quota", v.Revision, d.Generations, d.Day)
		}
		return nil
	})
	a := *p.Active
	// Expire under the same durable transaction used by the production store.
	f.cfg.dictationTransaction(f.owner, true, func(d *dictationData) error {
		dictationFind(d, "one").Playback.Active.LeaseUntil = time.Now().Add(-time.Second).UnixMilli()
		return nil
	})
	if w := f.call("POST", "/one/playback", playbackBody(a.ID, a.Client, "progress", 0, a.Fence)); w.Code != 409 {
		t.Fatal("expired progress", w.Code)
	}
	p = playbackDecode(t, f.call("POST", "/one/playback", playbackBody(a.ID, "handoff", "resume", 0, a.Fence)))
	if p.WholeStarts != 1 || p.Active.Fence <= a.Fence {
		t.Fatal(p)
	}
	if w := f.call("POST", "/one/playback", playbackBody(a.ID, a.Client, "ended", 0, a.Fence)); w.Code != 409 {
		t.Fatal("stale completion", w.Code)
	}
}
func TestDictationPlaybackSentencesFinalAndStrictInput(t *testing.T) {
	f := newPlaybackFixture(t)
	f.seed(t)
	for _, body := range []string{`{}`, `{"id":"x","client":"tab","action":"start","url":"https://example.com"}`, `{"id":"x","client":"tab","action":"start","offset":-1}`, `{"id":"x","client":"tab","action":"start","offset":7201}`, `{"id":"x","client":"tab","action":"start","fence":-1}`, `{"id":"x","client":"tab","action":"start","step":121}`, strings.Repeat(" ", 17000) + `{}`} {
		if w := f.call("POST", "/one/playback", body); w.Code != 400 {
			t.Fatal(w.Code, w.Body)
		}
	}
	if w := f.call("POST", "/one/playback", playbackBody("skip", "tab", "start", 2, 0)); w.Code != 409 {
		t.Fatal("skipped cursor", w.Code)
	}
	var record dictationRecord
	json.Unmarshal(f.call("GET", "/one", "").Body.Bytes(), &record)
	for step := 1; step < len(record.Plan); step++ {
		id := fmt.Sprint("s", step)
		p := playbackDecode(t, f.call("POST", "/one/playback", playbackBody(id, "tab", "start", step, 0)))
		if step < len(record.Plan)-1 && p.WholeStarts != 0 {
			t.Fatal("sentence consumed whole quota", p)
		}
		p = playbackDecode(t, f.call("POST", "/one/playback", playbackBody(id, "tab", "ended", step, p.Active.Fence)))
		if p.Active != nil {
			t.Fatal("automatic final reservation", p)
		}
	}
	if w := f.call("POST", "/one/playback", playbackBody("final-again", "tab", "start", len(record.Plan)-1, 0)); w.Code != 409 {
		t.Fatal("final replay repeated", w.Code)
	}
	// Media HEAD and Range use owner auth; safe reads need no mutation CSRF.
	r := httptest.NewRequest("HEAD", "/v1/learning/dictations/one/audio/0", nil)
	r.AddCookie(&http.Cookie{Name: browserCookie, Value: f.browser})
	w := httptest.NewRecorder()
	f.h.ServeHTTP(w, r)
	if w.Code != 200 || w.Body.Len() != 0 {
		t.Fatal("HEAD", w.Code, w.Body)
	}
	r = httptest.NewRequest("GET", "/v1/learning/dictations/one/audio/0", nil)
	r.Header.Set("Authorization", "Bearer "+f.token)
	r.Header.Set("Range", "bytes=0-8")
	w = httptest.NewRecorder()
	f.h.ServeHTTP(w, r)
	if w.Code != 206 || !bytes.Equal(w.Body.Bytes(), []byte("synthetic")) {
		t.Fatal("range", w.Code, w.Body)
	}
}
func TestDictationPlaybackAuthAndFailedCommit(t *testing.T) {
	f := newPlaybackFixture(t)
	f.seed(t)
	r := httptest.NewRequest("POST", "/v1/learning/dictations/one/playback", strings.NewReader(playbackBody("one", "tab", "start", 0, 0)))
	r.AddCookie(&http.Cookie{Name: browserCookie, Value: f.browser})
	w := httptest.NewRecorder()
	f.h.ServeHTTP(w, r)
	if w.Code != 403 {
		t.Fatal("CSRF", w.Code)
	}
	root := f.cfg.dictationRoot(f.owner)
	if e := os.Chmod(root, 0500); e != nil {
		t.Fatal(e)
	}
	defer os.Chmod(root, 0700)
	w = f.call("POST", "/one/playback", playbackBody("failed", "tab", "start", 0, 0))
	if w.Code != 503 {
		t.Fatal("success before durable commit", w.Code, w.Body)
	}
	os.Chmod(root, 0700)
	var record dictationRecord
	json.Unmarshal(f.call("GET", "/one", "").Body.Bytes(), &record)
	if record.Playback.WholeStarts != 0 {
		t.Fatal("failed write incremented quota", record.Playback)
	}
	// Expired native credentials cannot read cached media or reserve playback.
	f.cfg.auth.store.lock.locked(func() error {
		d, e := f.cfg.auth.store.read()
		if e != nil {
			return e
		}
		s := d.Sessions[sessionHash(f.token)]
		s.Expires = time.Now().Add(-time.Second)
		d.Sessions[sessionHash(f.token)] = s
		return f.cfg.auth.store.write(d)
	})
	for _, method := range []string{"GET", "HEAD", "POST"} {
		r := httptest.NewRequest(method, "/v1/learning/dictations/one/audio/0", strings.NewReader(`{}`))
		r.Header.Set("Authorization", "Bearer "+f.token)
		w := httptest.NewRecorder()
		f.h.ServeHTTP(w, r)
		if w.Code != 401 {
			t.Fatal("expired native media", method, w.Code)
		}
	}
	// Revoke the browser credential, then test every media method and playback.
	f.cfg.auth.store.lock.locked(func() error {
		d, e := f.cfg.auth.store.read()
		if e != nil {
			return e
		}
		delete(d.Sessions, sessionHash(f.browser))
		return f.cfg.auth.store.write(d)
	})
	for _, method := range []string{"GET", "HEAD", "POST"} {
		w = f.call(method, "/one/audio/0", `{}`)
		if w.Code != 401 {
			t.Fatal("revoked media", method, w.Code)
		}
	}
	if w = f.call("POST", "/one/playback", playbackBody("revoked", "tab", "start", 0, 0)); w.Code != 401 {
		t.Fatal("revoked start", w.Code)
	}
}

func TestDictationPlaybackCheckpointFencesAndCachedNewAttempt(t *testing.T) {
	f := newPlaybackFixture(t)
	f.seed(t)
	p := playbackDecode(t, f.call("POST", "/one/playback", playbackBody("whole", "tab", "start", 0, 0)))
	firstFence := p.Active.Fence
	p = playbackDecode(t, f.call("POST", "/one/playback", playbackBody("whole", "tab", "progress", 0, firstFence)))
	if p.Active.Fence <= firstFence {
		t.Fatal("checkpoint did not advance fence", p)
	}
	if w := f.call("POST", "/one/playback", playbackBody("whole", "tab", "progress", 0, firstFence)); w.Code != 409 {
		t.Fatal("reordered progress accepted", w.Code)
	}
	end := playbackBody("whole", "tab", "ended", 0, p.Active.Fence)
	playbackDecode(t, f.call("POST", "/one/playback", end))
	playbackDecode(t, f.call("POST", "/one/playback", playbackBody("next", "tab", "start", 0, 0)))
	playbackDecode(t, f.call("POST", "/one/playback", end)) // Older duplicate end must leave the new active play intact.
	var before dictationRecord
	json.Unmarshal(f.call("GET", "/one", "").Body.Bytes(), &before)
	if before.Playback.Active.ID != "next" || before.Playback.WholeStarts != 2 {
		t.Fatal(before.Playback)
	}
	body := `{"id":"fresh","playback_policy_version":1}`
	for i := 0; i < 2; i++ {
		w := f.call("POST", "/one/attempts", body)
		if w.Code != 200 {
			t.Fatal(w.Code, w.Body)
		}
		var next dictationRecord
		json.Unmarshal(w.Body.Bytes(), &next)
		if next.Playback.WholeStarts != 0 || next.Playback.Active != nil || len(next.Ready) != 3 {
			t.Fatal("fresh cached attempt", next)
		}
	}
	// Removing the source attempt cannot remove the new attempt's cached hardlinks.
	if w := f.call("DELETE", "/one", `{"revision":0}`); w.Code != 200 {
		t.Fatal(w.Code, w.Body)
	}
	if w := f.call("GET", "/fresh/audio/0", ""); w.Code != 200 {
		t.Fatal(w.Code, w.Body)
	}
	for _, version := range []string{`0`, `2`, `null`, `1.0`} {
		if w := f.call("POST", "/fresh/attempts", `{"id":"bad","playback_policy_version":`+version+`}`); w.Code != 400 {
			t.Fatal("unsupported attempt policy", w.Code)
		}
	}
}
