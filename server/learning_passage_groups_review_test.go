package main

import (
	"bytes"
	"fmt"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// Exercise the route after its initial authentication: a request can wait on
// either store lock while logout revokes the previously authenticated token.
func TestPassageGroupsReadRechecksRevocationBeforeMigration(t *testing.T) {
	cfg, _, token, _, j := learningFixture(t)
	store := cfg.learningStore(j.Owner)
	if err := store.transaction(func(d *learningData) error {
		d.Passages = []learningPassage{{j.ID, 0, j.Segments[0].Text}}
		return nil
	}, true); err != nil {
		t.Fatal(err)
	}
	before, err := os.ReadFile(store.lock.path)
	if err != nil {
		t.Fatal(err)
	}
	if err := cfg.auth.store.revoke(token, time.Now()); err != nil {
		t.Fatal(err)
	}
	r := httptest.NewRequest("GET", "/v1/learning/episodes/"+j.ID+"/passage-groups", nil)
	r.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	cfg.learningPassageGroupsHTTP(w, r, j.Owner, j.ID)
	if w.Code != 401 {
		t.Errorf("revoked in-flight read leaked groups: status %d", w.Code)
	}
	after, err := os.ReadFile(store.lock.path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Error("revoked read persisted migration")
	}
}

func TestPassageGroupsCoachRuneBoundaryNeverFallsBackToMembers(t *testing.T) {
	for _, size := range []int{1800, 1801} {
		t.Run(fmt.Sprint(size), func(t *testing.T) {
			cfg, h, token, _, j := learningFixture(t)
			source := &podcastStore{lock: &historyStore{path: filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json")}}
			if err := source.lock.locked(func() error {
				d, err := source.read()
				if err != nil {
					return err
				}
				d.Jobs[0].Segments = []podcastSegment{{Start: 0, End: 1, Text: strings.Repeat("ä", 900)}, {Start: 1, End: 2, Text: strings.Repeat("я", size-901)}}
				return source.write(d)
			}); err != nil {
				t.Fatal(err)
			}
			starGroup(t, h, token, j.ID, 0, true)
			starGroup(t, h, token, j.ID, 1, true)
			sources, err := cfg.coachSources(j.Owner)
			if err != nil {
				t.Fatal(err)
			}
			want := 1
			if size > 1800 {
				want = 0
			}
			if len(sources) != want {
				t.Fatalf("size %d: got %d candidates, want %d", size, len(sources), want)
			}
			if want == 1 && runeCount(sources[0].Text) != size {
				t.Fatal("group span truncated")
			}
		})
	}
}

func TestPassageGroupsCoachConcurrentAppendUsesOneSourceSnapshot(t *testing.T) {
	cfg, h, token, _, j := learningFixture(t)
	starGroup(t, h, token, j.ID, 0, true)
	source := &podcastStore{lock: &historyStore{path: filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json")}}
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 1; i <= 200; i++ {
			err := source.lock.locked(func() error {
				d, err := source.read()
				if err != nil {
					return err
				}
				d.Jobs[0].Segments = append(d.Jobs[0].Segments, podcastSegment{Start: float64(i + 10), End: float64(i + 11), Text: "x"})
				if err := source.write(d); err != nil {
					return err
				}
				return cfg.learningStore(j.Owner).transaction(func(ld *learningData) error {
					ld.Passages = append(ld.Passages, learningPassage{j.ID, i, "x"})
					return nil
				}, true)
			})
			if err != nil {
				t.Error(err)
				return
			}
		}
	}()
	defer wg.Wait()
	for i := 0; i < 200; i++ {
		err := func() (err error) {
			defer func() {
				if p := recover(); p != nil {
					err = fmt.Errorf("Coach used group indices from a newer transcript: %v", p)
				}
			}()
			_, err = cfg.coachSources(j.Owner)
			return err
		}()
		if err != nil {
			t.Fatal(err)
		}
	}
}
