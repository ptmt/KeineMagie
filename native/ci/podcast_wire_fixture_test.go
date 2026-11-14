// Run against the real server package with Go's -overlay; never accesses live data.
package main

import (
 "encoding/json"
 "os"
 "path/filepath"
 "testing"
 "time"
)

func TestNativePodcastWireFixture(t *testing.T) {
 root := os.Getenv("KM_PODCAST_WIRE_DIR")
 if root == "" { t.Fatal("KM_PODCAST_WIRE_DIR required") }
 store, err := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
 if err != nil { t.Fatal(err) }
 now := time.Date(2026, 11, 14, 0, 0, 0, 0, time.UTC)
 job := podcastJob{ID: "synthetic-job-000000001", Owner: "synthetic-owner", URL: "https://audio.example/raw.mp3", FeedID: "synthetic-feed-00000001", EpisodeID: "synthetic-episode", Title: "Saved episode title", SourceLanguage: "de", TargetLanguage: "ru", State: "completed", Progress: 100, CreatedAt: now, UpdatedAt: now}
 for i := 0; i < 2113; i++ { job.Segments = append(job.Segments, podcastSegment{Start: float64(i), End: float64(i+1), Text: "Synthetic transcript"}) }
 sub := podcastSubscription{ID: job.FeedID, URL: "https://audio.example/feed.xml", Title: "Saved feed", Episodes: []podcastEpisode{{ID: job.EpisodeID, Title: job.Title, URL: job.URL}}, RefreshedAt: now}
 data := podcastData{Jobs: []podcastStoredJob{{podcastJob: job, Owner: job.Owner}}, Budgets: map[string]podcastBudget{}, Subscriptions: []podcastStoredSubscription{{podcastSubscription: sub, Owner: job.Owner}}}
 if err := store.write(data); err != nil { t.Fatal(err) }
 subs, err := store.subscriptions(job.Owner)
 if err != nil { t.Fatal(err) }
 jobs, err := store.list(job.Owner)
 if err != nil { t.Fatal(err) }
 if len(subs) != 1 || subs[0].Episodes[0].Preparation == nil || subs[0].Episodes[0].Preparation.Segments != nil || len(jobs) != 1 || len(jobs[0].Segments) != 2113 { t.Fatal("wire shape mismatch") }
 foreign, err := store.subscriptions("another-owner")
 if err != nil || len(foreign) != 0 { t.Fatal("owner isolation failed") }
 for name, value := range map[string]any{
  "subscriptions.json": map[string]any{"items": subs},
  "library.json": map[string]any{"items": jobs, "worker_available": false},
  "empty-subscription.json": podcastSubscription{ID: "synthetic-empty-feed-001", URL: sub.URL, Title: "Empty feed"},
 } {
  bytes, err := json.Marshal(value)
  if err != nil { t.Fatal(err) }
  if err = os.WriteFile(filepath.Join(root, name), bytes, 0600); err != nil { t.Fatal(err) }
 }
}
