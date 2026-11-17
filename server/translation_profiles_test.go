package main

import (
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

func profileBody(op, id string, revision int, title, instruction string) string {
	b, _ := json.Marshal(map[string]any{"operation_id": op, "id": id, "base_revision": revision, "title": title, "instruction": instruction})
	return string(b)
}
func profileRead(t *testing.T, h http.Handler, token string) translationProfiles {
	t.Helper()
	w := authCall(h, "GET", "/v1/translation-profiles", "", token)
	var d translationProfiles
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &d) != nil {
		t.Fatalf("read %d %s", w.Code, w.Body.String())
	}
	return d
}
func TestTranslationProfilesConflictsTombstonesAndReceipts(t *testing.T) {
	_, h, a, b, _ := historyFixture(t)
	create := profileBody("import-one", "one", 0, "Same", "First")
	if w := authCall(h, "PUT", "/v1/translation-profiles", create, a); w.Code != 200 {
		t.Fatal(w.Code)
	}
	for _, body := range []string{profileBody("import-one", "one", 0, "Same", "Different"), profileBody("other-op", "one", 0, "Same", "Different")} {
		if w := authCall(h, "PUT", "/v1/translation-profiles", body, b); w.Code != 409 {
			t.Fatal("overwritten", w.Code)
		}
	}
	if w := authCall(h, "PATCH", "/v1/translation-profiles", profileBody("rename", "one", 1, "Renamed", "First"), a); w.Code != 200 {
		t.Fatal(w.Code)
	}
	if w := authCall(h, "PATCH", "/v1/translation-profiles", profileBody("stale", "one", 1, "Offline", "First"), b); w.Code != 409 {
		t.Fatal("stale overwrite", w.Code)
	}
	if w := authCall(h, "DELETE", "/v1/translation-profiles", profileBody("delete", "one", 2, "", ""), a); w.Code != 200 {
		t.Fatal(w.Code)
	}
	if w := authCall(h, "PUT", "/v1/translation-profiles", create, b); w.Code != 200 {
		t.Fatal("replay", w.Code)
	}
	if w := authCall(h, "PUT", "/v1/translation-profiles", profileBody("recreate", "one", 0, "Same", "First"), b); w.Code != 409 {
		t.Fatal("resurrected", w.Code)
	}
	d := profileRead(t, h, a)
	if d.Revision != 3 || len(d.Items) != 1 || !d.Items[0].Deleted || d.Items[0].Title != "" || d.Receipts != nil {
		t.Fatalf("bad tombstone %+v", d)
	}
}
func TestTranslationProfilesConcurrentDistinctSameNamePreserveOrder(t *testing.T) {
	_, h, a, b, _ := historyFixture(t)
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			token := a
			if i%2 == 0 {
				token = b
			}
			body := profileBody(fmt.Sprint("op-", i), fmt.Sprint("id-", i), 0, "Same name", fmt.Sprint("instruction-", i))
			w := authCall(h, "PUT", "/v1/translation-profiles", body, token)
			if w.Code != 200 {
				t.Errorf("create %d", w.Code)
			}
		}(i)
	}
	wg.Wait()
	d := profileRead(t, h, a)
	if len(d.Items) != 20 || d.Revision != 20 {
		t.Fatalf("lost records %d %d", len(d.Items), d.Revision)
	}
	first := d.Items[0]
	if w := authCall(h, "PATCH", "/v1/translation-profiles", profileBody("rename", first.ID, int(first.Revision), "New title", first.Instruction), b); w.Code != 200 {
		t.Fatal(w.Code)
	}
	after := profileRead(t, h, a)
	for i := range d.Items {
		if after.Items[i].ID != d.Items[i].ID {
			t.Fatal("reordered")
		}
	}
}
func TestTranslationProfilesRejectLossyJSONUnicode(t *testing.T) {
	_, h, a, _, _ := historyFixture(t)
	for _, title := range []string{string([]byte{'"', 0xff, '"'}), `"\ud800"`, `"\udc00"`, `"\ud800x"`} {
		body := `{"operation_id":"unicode","id":"unicode","base_revision":0,"title":` + title + `,"instruction":"Text"}`
		if w := authCall(h, "PUT", "/v1/translation-profiles", body, a); w.Code != 400 {
			t.Errorf("lossy JSON accepted: %d", w.Code)
		}
	}
	if d := profileRead(t, h, a); d.Revision != 0 {
		t.Fatal("invalid Unicode persisted")
	}
	body := `{"operation_id":"valid","id":"valid","base_revision":0,"title":"\ud83d\ude42 \\ud800 �","instruction":"Text"}`
	if w := authCall(h, "PUT", "/v1/translation-profiles", body, a); w.Code != 200 {
		t.Fatalf("valid Unicode rejected: %d", w.Code)
	}
}

func TestTranslationProfilesUnicodeAndStrictValidation(t *testing.T) {
	_, h, a, _, _ := historyFixture(t)
	for _, body := range []string{`null`, `{}`, `{"id":"a","operation_id":"b","owner":"foreign"}`, profileBody("x", "friendly", 0, "Title", "Do it"), profileBody("x", "a", 0, strings.Repeat("🙂", 61), "Do it"), profileBody("x", "a", 0, "Title", strings.Repeat("🙂", 1001)), profileBody("x", "../a", 0, "Title", "Do it"), profileBody("x", "a", -1, "Title", "Do it")} {
		if w := authCall(h, "PUT", "/v1/translation-profiles", body, a); w.Code != 400 {
			t.Fatalf("invalid accepted %d", w.Code)
		}
	}
	body := profileBody("valid", "a", 0, strings.Repeat("🙂", 60), strings.Repeat("é", 500))
	if w := authCall(h, "PUT", "/v1/translation-profiles", body, a); w.Code != 200 {
		t.Fatalf("scalar boundary %d %s", w.Code, w.Body.String())
	}
	if profileRead(t, h, a).Revision != 1 {
		t.Fatal("invalid writes changed store")
	}
}
func TestTranslationProfilesIsolationCSRFExpectedOwnerRevocationAndFailure(t *testing.T) {
	t.Setenv("WEB_ORIGIN", "https://example.com")
	cfg, h, a, _, _ := historyFixture(t)
	s, _ := cfg.auth.store.lookup(a, time.Now())
	browser, e := cfg.auth.store.createBrowser(a, s.UserID, time.Now())
	if e != nil {
		t.Fatal(e)
	}
	body := profileBody("op", "one", 0, "Title", "Instruction")
	for _, tc := range []struct {
		origin, csrf, owner string
		code                int
	}{{"https://evil.invalid", browserCSRF(browser), "", 403}, {"https://example.com", "", "", 403}, {"https://example.com", browserCSRF(browser), "foreign", 403}, {"https://example.com", browserCSRF(browser), s.UserID, 200}} {
		r := httptest.NewRequest("PUT", "/v1/translation-profiles", strings.NewReader(body))
		r.AddCookie(&http.Cookie{Name: browserCookie, Value: browser})
		r.Header.Set("Origin", tc.origin)
		r.Header.Set("X-CSRF-Token", tc.csrf)
		r.Header.Set("X-Translation-Owner", tc.owner)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != tc.code {
			t.Fatalf("auth %d %s", w.Code, w.Body.String())
		}
	}
	other, _, _ := cfg.auth.store.create("other-owner", time.Now())
	if len(profileRead(t, h, other).Items) != 0 {
		t.Fatal("cross owner")
	}
	path := cfg.profileLock(s.UserID).path
	info, e := os.Stat(path)
	if e != nil || info.Mode().Perm() != 0600 {
		t.Fatalf("permissions %v %v", info, e)
	}
	if e = os.Remove(path); e != nil {
		t.Fatal(e)
	}
	if e = os.Mkdir(path, 0700); e != nil {
		t.Fatal(e)
	}
	if w := authCall(h, "PUT", "/v1/translation-profiles", body, a); w.Code != 503 {
		t.Fatal("failure acknowledged", w.Code)
	}
	if e = cfg.auth.store.revoke(a, time.Now()); e != nil {
		t.Fatal(e)
	}
	if w := authCall(h, "GET", "/v1/translation-profiles", "", a); w.Code != 401 {
		t.Fatal("revoked", w.Code)
	}
}

type profileHeldBody struct {
	*strings.Reader
	entered chan struct{}
	release chan struct{}
	once    sync.Once
}

func (b *profileHeldBody) Read(p []byte) (int, error) {
	b.once.Do(func() { close(b.entered); <-b.release })
	return b.Reader.Read(p)
}
func (b *profileHeldBody) Close() error { return nil }
func TestTranslationProfilesRevocationWhileWriteBodyIsPending(t *testing.T) {
	cfg, h, a, _, _ := historyFixture(t)
	s, err := cfg.auth.store.lookup(a, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	body := &profileHeldBody{Reader: strings.NewReader(profileBody("held", "held", 0, "Private", "Text")), entered: make(chan struct{}), release: make(chan struct{})}
	r := httptest.NewRequest("PUT", "/v1/translation-profiles", body)
	r.Header.Set("Authorization", "Bearer "+a)
	w := httptest.NewRecorder()
	done := make(chan struct{})
	go func() { h.ServeHTTP(w, r); close(done) }()
	<-body.entered
	if err := cfg.auth.store.revoke(a, time.Now()); err != nil {
		close(body.release)
		t.Fatal(err)
	}
	close(body.release)
	<-done
	if w.Code != 401 {
		t.Fatalf("revoked write accepted: %d", w.Code)
	}
	if _, err := os.Stat(cfg.profileLock(s.UserID).path); !os.IsNotExist(err) {
		t.Fatalf("revoked write touched private store: %v", err)
	}
}

func TestTranslationProfilesAtomicWriteFailureDoesNotAcknowledge(t *testing.T) {
	cfg, h, a, _, _ := historyFixture(t)
	s, _ := cfg.auth.store.lookup(a, time.Now())
	first := profileBody("first", "one", 0, "Title", "Instruction")
	if w := authCall(h, "PUT", "/v1/translation-profiles", first, a); w.Code != 200 {
		t.Fatal(w.Code)
	}
	directory := filepath.Dir(cfg.profileLock(s.UserID).path)
	if e := os.Chmod(directory, 0500); e != nil {
		t.Fatal(e)
	}
	defer os.Chmod(directory, 0700)
	w := authCall(h, "PATCH", "/v1/translation-profiles", profileBody("edit", "one", 1, "Changed", "Instruction"), a)
	if w.Code != 503 {
		t.Fatalf("failed save acknowledged %d", w.Code)
	}
	if e := os.Chmod(directory, 0700); e != nil {
		t.Fatal(e)
	}
	d := profileRead(t, h, a)
	if d.Revision != 1 || d.Items[0].Title != "Title" {
		t.Fatal("failed write persisted")
	}
	w = authCall(h, "PATCH", "/v1/translation-profiles", profileBody("edit", "one", 1, "Changed", "Instruction"), a)
	if w.Code != 200 {
		t.Fatalf("retry could not save %d", w.Code)
	}
}
func TestTranslationProfilesFiftyLiveLimitAllowsReplayAndDelete(t *testing.T) {
	_, h, a, _, _ := historyFixture(t)
	for i := 0; i < 50; i++ {
		body := profileBody(fmt.Sprint("op-", i), fmt.Sprint("id-", i), 0, "Same", "Content")
		if w := authCall(h, "PUT", "/v1/translation-profiles", body, a); w.Code != 200 {
			t.Fatal(i, w.Code)
		}
	}
	if w := authCall(h, "PUT", "/v1/translation-profiles", profileBody("over", "over", 0, "Title", "Text"), a); w.Code != 422 {
		t.Fatal("limit", w.Code)
	}
	if w := authCall(h, "PUT", "/v1/translation-profiles", profileBody("op-0", "id-0", 0, "Same", "Content"), a); w.Code != 200 {
		t.Fatal("replay at capacity", w.Code)
	}
	if w := authCall(h, "DELETE", "/v1/translation-profiles", profileBody("delete", "id-0", 1, "", ""), a); w.Code != 200 {
		t.Fatal("delete at capacity", w.Code)
	}
	if w := authCall(h, "PUT", "/v1/translation-profiles", profileBody("over", "over", 0, "Title", "Text"), a); w.Code != 200 {
		t.Fatal("new space", w.Code)
	}
}

func TestTranslationProfilesTwoClientsRestart(t *testing.T) {
	cfg, h, a, b, _ := historyFixture(t)
	body := `{"operation_id":"create-one","id":"custom-one","base_revision":0,"title":"仕事 🙂","instruction":"Keep all meaning."}`
	w := authCall(h, "PUT", "/v1/translation-profiles", body, a)
	if w.Code != 200 {
		t.Fatalf("create: %d %s", w.Code, w.Body.String())
	}
	w = authCall(h, "PUT", "/v1/translation-profiles", body, b)
	if w.Code != 200 {
		t.Fatal("lost-ack replay", w.Code)
	}
	restarted, e := newHandler(&serverConfig{authPath: cfg.authPath, historyPath: cfg.historyPath})
	if e != nil {
		t.Fatal(e)
	}
	w = authCall(restarted, "GET", "/v1/translation-profiles", "", b)
	var value struct {
		Revision int `json:"revision"`
		Items    []struct {
			ID    string `json:"id"`
			Title string `json:"title"`
		} `json:"items"`
	}
	if e = json.Unmarshal(w.Body.Bytes(), &value); e != nil || w.Code != 200 || value.Revision != 1 || len(value.Items) != 1 || value.Items[0].Title != "仕事 🙂" {
		t.Fatalf("restart: %d %s", w.Code, w.Body.String())
	}
}
