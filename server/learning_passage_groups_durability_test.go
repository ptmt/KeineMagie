package main

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func TestPassageGroupsFailedAtomicWriteDoesNotAcknowledgeOrLoseLedger(t *testing.T) {
	cfg, h, token, _, j := learningFixture(t)
	starGroup(t, h, token, j.ID, 0, true)
	path := cfg.learningStore(j.Owner).lock.path
	before, e := os.ReadFile(path)
	if e != nil {
		t.Fatal(e)
	}
	dir := filepath.Dir(path)
	if e = os.Chmod(dir, 0500); e != nil {
		t.Fatal(e)
	}
	defer os.Chmod(dir, 0700)
	w := authCall(h, "PUT", "/v1/learning/episodes/"+j.ID+"/passages/0", `{"favorite":false}`, token)
	if w.Code != 503 {
		t.Fatalf("failed atomic save acknowledged: %d", w.Code)
	}
	after, e := os.ReadFile(path)
	if e != nil {
		t.Fatal(e)
	}
	if !bytes.Equal(before, after) {
		t.Fatal("failed write changed prior durable ledger")
	}
}
func TestPassageGroups2113OriginalIDsAndOwnerJobIsolation(t *testing.T) {
	cfg, h, token, _, j := learningFixture(t)
	s, _ := openPodcastStore(filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json"))
	err := s.lock.locked(func() error {
		d, e := s.read()
		if e != nil {
			return e
		}
		d.Jobs[0].Segments = nil
		for i := 0; i < 2113; i++ {
			d.Jobs[0].Segments = append(d.Jobs[0].Segments, podcastSegment{Start: float64(i), End: float64(i + 1), Text: fmt.Sprintf("Synthetic segment %d", i)})
		}
		j = storedPodcast(d.Jobs[0])
		return s.write(d)
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, i := range []int{2012, 2014, 2112} {
		starGroup(t, h, token, j.ID, i, true)
	}
	out := readGroups(t, h, token, j.ID)
	if len(out.Groups) != 3 {
		t.Fatal("nonadjacent search matches were merged")
	}
	starGroup(t, h, token, j.ID, 2013, true)
	out = readGroups(t, h, token, j.ID)
	if len(out.Groups) != 2 || len(out.Groups[0].SegmentIDs) != 3 {
		t.Fatal("long transcript bridge")
	}
	// Same numeric segment in another owner/job must have a different relationship ID.
	original := passageGroupsFor("A", j, []learningPassage{{j.ID, 2012, j.Segments[2012].Text}})[0]
	foreign := passageGroupsFor("B", j, []learningPassage{{j.ID, 2012, j.Segments[2012].Text}})[0]
	j.ID = "another-job"
	otherJob := passageGroupsFor("A", j, []learningPassage{{j.ID, 2012, j.Segments[2012].Text}})[0]
	if original.ID == foreign.ID || original.ID == otherJob.ID {
		t.Fatal("group identity crossed scope")
	}
}
func TestPassageGroupsDeleteRaceCannotResurrectReferences(t *testing.T) {
	cfg, h, token, _, j := learningFixture(t)
	var wg sync.WaitGroup
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			w := authCall(h, "PUT", "/v1/learning/episodes/"+j.ID+"/passages/0", `{"favorite":true}`, token)
			if w.Code != 200 && w.Code != 404 {
				t.Errorf("race write: %d", w.Code)
			}
		}()
	}
	w := authCall(h, "DELETE", "/v1/podcasts/"+j.ID, "", token)
	if w.Code != 204 {
		t.Fatal(w.Code)
	}
	wg.Wait()
	if e := cfg.learningStore(j.Owner).transaction(func(d *learningData) error {
		if len(d.Passages) != 0 || len(d.PassageGroups) != 0 {
			t.Error("race left orphan")
		}
		return nil
	}, false); e != nil {
		t.Fatal(e)
	}
}
func TestPassageGroupsRecoverInterruptedDeletionEvenForLastJob(t *testing.T) {
	cfg, h, token, _, j := learningFixture(t)
	starGroup(t, h, token, j.ID, 0, true)
	s, _ := openPodcastStore(filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json"))
	if e := s.lock.locked(func() error {
		d, e := s.read()
		if e != nil {
			return e
		}
		d.Jobs = []podcastStoredJob{}
		return s.write(d)
	}); e != nil {
		t.Fatal(e)
	}
	if w := authCall(h, "GET", "/v1/learning/episodes/"+j.ID+"/passage-groups", "", token); w.Code != 404 {
		t.Fatal(w.Code)
	}
	if e := cfg.learningStore(j.Owner).transaction(func(d *learningData) error {
		if len(d.Passages) != 0 || len(d.PassageGroups) != 0 {
			t.Error("interrupted deletion retained orphans")
		}
		return nil
	}, false); e != nil {
		t.Fatal(e)
	}
}

func TestPassageGroupsRevokedTokenCannotReadOrWrite(t *testing.T) {
	cfg, h, token, _, j := learningFixture(t)
	starGroup(t, h, token, j.ID, 0, true)
	if err := cfg.auth.store.revoke(token, time.Now()); err != nil {
		t.Fatal(err)
	}
	for _, method := range []string{"GET", "PUT"} {
		path := "/v1/learning/episodes/" + j.ID + "/passage-groups"
		if method == "PUT" {
			path = "/v1/learning/episodes/" + j.ID + "/passages/0"
		}
		if w := authCall(h, method, path, `{"favorite":false}`, token); w.Code != 401 {
			t.Fatalf("revoked %s: %d", method, w.Code)
		}
	}
}
