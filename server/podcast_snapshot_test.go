package main

import (
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func TestPodcastListLimitsShareSnapshot(t *testing.T) {
	s, err := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; i < 100; i++ {
			err := s.lock.locked(func() error {
				d := podcastData{Jobs: []podcastStoredJob{}, Budgets: map[string]podcastBudget{}}
				if i%2 == 0 {
					d.Jobs = append(d.Jobs, podcastStoredJob{podcastJob: podcastJob{ID: "job", State: "queued"}, Owner: "owner"})
				}
				return s.write(d)
			})
			if err != nil {
				t.Error(err)
				return
			}
		}
	}()
	defer wg.Wait()
	for i := 0; i < 100; i++ {
		jobs, limits, err := s.listWithLimits("owner", now)
		if err != nil {
			t.Fatal(err)
		}
		if len(jobs) != limits.Retained || len(jobs) != limits.Active {
			t.Fatal("mixed snapshot")
		}
	}
}
