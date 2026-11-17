package main

import (
	"io"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type passageBodySignal struct {
	io.Reader
	done chan struct{}
}

func (b passageBodySignal) Close() error { close(b.done); return nil }
func TestPassageGroupsQueuedMutationRechecksRevocation(t *testing.T) {
	cfg, h, token, _, j := learningFixture(t)
	s := &podcastStore{lock: &historyStore{path: filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json")}}
	held, release, finished := make(chan struct{}), make(chan struct{}), make(chan struct{})
	go func() { defer close(finished); _ = s.lock.locked(func() error { close(held); <-release; return nil }) }()
	<-held
	body := passageBodySignal{strings.NewReader(`{"favorite":true}`), make(chan struct{})}
	r := httptest.NewRequest("PUT", "/v1/learning/episodes/"+j.ID+"/passages/0", nil)
	r.Body = body
	r.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	done := make(chan struct{})
	go func() { defer close(done); h.ServeHTTP(w, r) }()
	<-body.done // authenticated and decoded, now blocked on source lock
	if e := cfg.auth.store.revoke(token, time.Now()); e != nil {
		t.Error(e)
	}
	close(release)
	<-finished
	<-done
	if w.Code != 401 {
		t.Fatalf("queued revoked write acknowledged: %d", w.Code)
	}
}

func TestPassageGroupsEmptyReadsDoNotAdvanceRevision(t *testing.T) {
	_, h, token, _, j := learningFixture(t)
	a := readGroups(t, h, token, j.ID)
	b := readGroups(t, h, token, j.ID)
	if a.Revision != b.Revision {
		t.Fatalf("empty read advanced revision: %d -> %d", a.Revision, b.Revision)
	}
}
func TestPassageGroupsExpectedOwnerFailsBeforeWork(t *testing.T) {
	_, h, token, _, j := learningFixture(t)
	for _, method := range []string{"GET", "PUT"} {
		path := "/v1/learning/episodes/" + j.ID + "/passage-groups"
		if method == "PUT" {
			path = "/v1/learning/episodes/" + j.ID + "/passages/0"
		}
		r := httptest.NewRequest(method, path, strings.NewReader(`{"favorite":true}`))
		r.Header.Set("Authorization", "Bearer "+token)
		r.Header.Set("X-Passage-Owner", "other-owner")
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != 403 {
			t.Fatalf("owner fence: %d", w.Code)
		}
	}
}
