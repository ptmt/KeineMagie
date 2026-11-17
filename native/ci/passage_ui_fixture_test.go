// Synthetic loopback acceptance server. Run only through the Go test overlay.
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestNativePassageUIFixture(t *testing.T) {
	if os.Getenv("KM_PASSAGE_UI_FIXTURE") != "1" {
		t.Skip("explicit synthetic fixture only")
	}
	cfg, production, token, other, job := learningFixture(t)
	store, err := openPodcastStore(filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json"))
	if err != nil {
		t.Fatal(err)
	}
	job.Title = "Synthetic passage acceptance"
	job.FeedID = "synthetic-passage-feed-01"
	job.EpisodeID = "passage-one"
	job.Segments = nil
	for i := 0; i < 2113; i++ {
		text := fmt.Sprintf("Synthetic segment %d", i)
		if i == 2012 || i == 2014 {
			text += " needle"
		}
		job.Segments = append(job.Segments, podcastSegment{Start: float64(i * 10), End: float64(i*10 + 8), Text: text, Translation: fmt.Sprintf("Перевод %d", i)})
	}
	if err = store.lock.locked(func() error {
		d, e := store.read()
		if e != nil {
			return e
		}
		for i := range d.Jobs {
			if d.Jobs[i].ID == job.ID {
				d.Jobs[i].Title = job.Title
				d.Jobs[i].Segments = job.Segments
				d.Jobs[i].FeedID = job.FeedID
				d.Jobs[i].EpisodeID = job.EpisodeID
			}
		}
		d.Subscriptions = []podcastStoredSubscription{{podcastSubscription: podcastSubscription{ID: job.FeedID, URL: "https://example.com/fixture.xml", Title: "Synthetic passage feed", Episodes: []podcastEpisode{{ID: job.EpisodeID, Title: job.Title, URL: job.URL}}}, Owner: job.Owner}}
		return store.write(d)
	}); err != nil {
		t.Fatal(err)
	}
	original, _ := json.Marshal(job.Segments)
	var mu sync.Mutex
	records := []map[string]any{}
	ownerB := false
	failNext := false
	revoked := false
	done := make(chan struct{})
	listener, err := net.Listen("tcp", "127.0.0.1:18879")
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{ReadHeaderTimeout: 5 * time.Second}
	server.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		respond := func(value any) { w.Header().Set("Content-Type", "application/json"); json.NewEncoder(w).Encode(value) }
		if r.URL.Path == "/_fixture/stop" {
			respond(map[string]bool{"stopped": true})
			close(done)
			return
		}
		if r.URL.Path == "/_fixture/reset" {
			for _, id := range readGroups(t, production, token, job.ID).FavoriteSegmentIDs {
				starGroup(t, production, token, job.ID, id, false)
			}
			records = []map[string]any{}
			ownerB = false
			failNext = false
			revoked = false
			respond(map[string]string{"job_id": job.ID})
			return
		}
		if r.URL.Path == "/_fixture/owner-b" {
			ownerB = true
			respond(map[string]bool{"ok": true})
			return
		}
		if r.URL.Path == "/_fixture/fail-next" {
			failNext = true
			respond(map[string]bool{"ok": true})
			return
		}
		if r.URL.Path == "/_fixture/revoke" {
			revoked = true
			respond(map[string]bool{"ok": true})
			return
		}
		if r.URL.Path == "/_fixture/state" {
			groups := readGroups(t, production, token, job.ID)
			current, e := cfg.learningJob(job.Owner, job.ID)
			if e != nil {
				t.Error(e)
			}
			data, _ := json.Marshal(current.Segments)
			respond(map[string]any{"requests": records, "groups": groups, "source_unchanged": bytes.Equal(original, data), "source_sha256": fmt.Sprintf("%x", sha256.Sum256(data)), "segment_count": len(current.Segments)})
			return
		}
		if r.Method != "GET" && !(r.Method == "PUT" && strings.Contains(r.URL.Path, "/passages/")) {
			http.Error(w, "fixture forbids provider or unrelated mutations", 403)
			return
		}
		body, _ := io.ReadAll(r.Body)
		r.Body = io.NopCloser(bytes.NewReader(body))
		capturedOwner := r.Header.Get("X-Passage-Owner")
		selectedToken := token
		if ownerB {
			selectedToken = other
		}
		r.Header.Set("Authorization", "Bearer "+selectedToken)
		result := httptest.NewRecorder()
		if revoked {
			result.WriteHeader(401)
		} else if failNext && r.Method == "PUT" {
			failNext = false
			result.WriteHeader(503)
		} else {
			production.ServeHTTP(result, r)
		}
		record := map[string]any{"method": r.Method, "path": r.URL.Path, "body": string(body), "owner": capturedOwner, "status": result.Code}
		if strings.Contains(r.URL.Path, "/passage") {
			record["response"] = result.Body.String()
		}
		records = append(records, record)
		for k, vs := range result.Header() {
			for _, v := range vs {
				w.Header().Add(k, v)
			}
		}
		w.WriteHeader(result.Code)
		w.Write(result.Body.Bytes())
	})
	go func() {
		if e := server.Serve(listener); e != nil && e != http.ErrServerClosed {
			t.Error(e)
		}
	}()
	fmt.Println("PASSAGE_FIXTURE_READY 127.0.0.1:18879 synthetic-only")
	select {
	case <-done:
	case <-time.After(90 * time.Minute):
		t.Error("fixture deadline")
	}
	server.Close()
	// Reconstruct the real handler/store and verify durable state independently.
	fresh, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	before := readGroups(t, production, token, job.ID)
	after := readGroups(t, fresh, token, job.ID)
	b, _ := json.Marshal(before)
	a, _ := json.Marshal(after)
	if !bytes.Equal(a, b) {
		t.Fatal("groups changed after store/handler reconstruction")
	}
	t.Logf("durable production handler reconstruction verified: %d groups", len(after.Groups))
}
