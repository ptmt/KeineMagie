package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"
)

// Real OS subprocesses share only durable files. Servers below are explicit
// synthetic worker/provider wire fixtures, never recognition/provider claims.
func TestPodcastResumeSubprocess(t *testing.T) {
	if os.Getenv("PODCAST_RESUME_CHILD") != "1" {
		return
	}
	root := os.Getenv("PODCAST_RESUME_ROOT")
	cfg := &serverConfig{authPath: filepath.Join(root, "auth.json"), historyPath: filepath.Join(root, "history.json")}
	target, _ := url.Parse(os.Getenv("PODCAST_RESUME_PROVIDER"))
	cfg.httpClient = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		r.URL.Scheme = target.Scheme
		r.URL.Host = target.Host
		r.Host = target.Host
		return http.DefaultTransport.RoundTrip(r)
	})}
	if _, e := newHandler(cfg); e != nil {
		t.Fatal(e)
	}
	if e := cfg.provider.save("owner", providerCredential{AccessToken: "synthetic", Expires: time.Now().Add(time.Hour)}); e != nil {
		t.Fatal(e)
	}
	s, e := openPodcastStore(filepath.Join(root, "podcasts", "jobs.json"))
	if e != nil {
		t.Fatal(e)
	}
	remote, e := newPodcastRemote(os.Getenv("PODCAST_RESUME_WORKER"), filepath.Join(root, "token"))
	if e != nil {
		t.Fatal(e)
	}
	p := &podcastService{cfg: cfg, store: s, remote: remote, fetchAudio: func(ctx context.Context, _, dest string) error {
		u, _ := url.Parse(os.Getenv("PODCAST_RESUME_SOURCE"))
		return podcastFetchHTTP(ctx, u, dest, http.DefaultClient)
	}}
	p.run(context.Background())
}

func TestPodcastSIGKILLRecovery(t *testing.T) {
	for _, phase := range []string{"recognition", "download", "translation"} {
		t.Run(phase, func(t *testing.T) {
			root := t.TempDir()
			s, e := openPodcastStore(filepath.Join(root, "podcasts", "jobs.json"))
			if e != nil {
				t.Fatal(e)
			}
			_, e = s.create("owner", "https://example.com/fixture.mp3", "de", time.Now())
			if e != nil {
				t.Fatal(e)
			}
			_ = os.WriteFile(filepath.Join(root, "token"), []byte(strings.Repeat("a", 64)), 0600)
			_ = os.WriteFile(filepath.Join(root, "key"), []byte(strings.Repeat("k", 32)), 0600)
			var mu sync.Mutex
			downloads, workerCalls, providerCalls := 0, 0, 0
			offsets := []string{}
			ids := [][]int{}
			source := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				mu.Lock()
				downloads++
				n := downloads
				mu.Unlock()
				w.Header().Set("Content-Type", "audio/mpeg")
				if phase == "download" && n == 1 {
					io.WriteString(w, "partial")
					w.(http.Flusher).Flush()
					<-r.Context().Done()
					return
				}
				io.WriteString(w, "complete synthetic encoded bytes")
			}))
			defer source.Close()
			worker := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if strings.HasSuffix(r.URL.Path, "ready") {
					io.WriteString(w, `{"version":1,"ready":true,"capacity":1}`)
					return
				}
				_, _ = io.Copy(io.Discard, r.Body)
				mu.Lock()
				workerCalls++
				n := workerCalls
				offsets = append(offsets, r.Header.Get("X-Resume-Offset"))
				mu.Unlock()
				w.Header().Set("Content-Type", "application/x-ndjson")
				if phase == "recognition" && n == 1 {
					io.WriteString(w, "{\"type\":\"checkpoint\",\"chunk_index\":0,\"end_seconds\":600,\"segments\":[{\"start\":0,\"end\":1,\"text\":\"first\"}]}\n")
					w.(http.Flusher).Flush()
					<-r.Context().Done()
					return
				}
				index := 0
				end := 10.0
				segments := []podcastSegment{{Start: 1, End: 2, Text: "last marker"}}
				if phase == "recognition" {
					index = 1
					end = 660
					segments[0].Start = 650
					segments[0].End = 652
				}
				if phase == "translation" {
					end = 600
					segments = nil
					for i := 0; i < 65; i++ {
						segments = append(segments, podcastSegment{Start: float64(i * 2), End: float64(i*2 + 1), Text: "word"})
					}
				}
				_ = json.NewEncoder(w).Encode(map[string]any{"type": "checkpoint", "chunk_index": index, "end_seconds": end, "segments": segments})
				_ = json.NewEncoder(w).Encode(map[string]any{"type": "complete", "duration_seconds": end, "language": "de"})
			}))
			defer worker.Close()
			provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if !strings.HasSuffix(r.URL.Path, "responses") {
					io.WriteString(w, `{"models":[{"slug":"offered","display_name":"Synthetic","visibility":"list"}]}`)
					return
				}
				var req struct {
					Input []struct {
						Content string `json:"content"`
					} `json:"input"`
				}
				_ = json.NewDecoder(r.Body).Decode(&req)
				var in struct {
					Segments []podcastTranslationItem `json:"segments"`
				}
				_ = json.Unmarshal([]byte(req.Input[0].Content), &in)
				batchIDs := []int{}
				for i := range in.Segments {
					batchIDs = append(batchIDs, in.Segments[i].ID)
					in.Segments[i].Text = "перевод"
				}
				mu.Lock()
				providerCalls++
				n := providerCalls
				ids = append(ids, batchIDs)
				mu.Unlock()
				if phase == "translation" && n == 2 {
					w.Header().Set("Content-Type", "text/event-stream")
					w.WriteHeader(200)
					w.(http.Flusher).Flush()
					<-r.Context().Done()
					return
				}
				b, _ := json.Marshal(map[string]any{"segments": in.Segments})
				io.WriteString(w, accountTranslationSSE(string(b), true, "response.completed"))
			}))
			defer provider.Close()
			launch := func() *exec.Cmd {
				cmd := exec.Command(os.Args[0], "-test.run=^TestPodcastResumeSubprocess$", "-test.timeout=40s")
				cmd.Env = append(os.Environ(), "PODCAST_RESUME_CHILD=1", "PODCAST_RESUME_ROOT="+root, "PODCAST_RESUME_WORKER="+worker.URL, "PODCAST_RESUME_PROVIDER="+provider.URL, "PODCAST_RESUME_SOURCE="+source.URL, "PODCAST_WORKER_URL=", "PROVIDER_KEY_FILE="+filepath.Join(root, "key"))
				cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
				cmd.Stdout = os.Stdout
				cmd.Stderr = os.Stderr
				if e := cmd.Start(); e != nil {
					t.Fatal(e)
				}
				return cmd
			}
			wait := func(predicate func() bool) {
				deadline := time.Now().Add(15 * time.Second)
				for time.Now().Before(deadline) {
					if predicate() {
						return
					}
					time.Sleep(20 * time.Millisecond)
				}
				t.Fatal("timed out waiting for " + phase)
			}
			child := launch()
			defer func() {
				if child != nil {
					_ = child.Process.Kill()
					_ = child.Wait()
				}
			}()
			wait(func() bool {
				jobs, _ := s.list("owner")
				if len(jobs) != 1 {
					return false
				}
				switch phase {
				case "recognition":
					return jobs[0].Resume != nil && jobs[0].Resume.End == 600
				case "download":
					files, _ := filepath.Glob(filepath.Join(root, "podcasts", "media", "*.partial"))
					if len(files) == 0 {
						return false
					}
					st, _ := os.Stat(files[0])
					return st != nil && st.Size() > 0
				default:
					mu.Lock()
					n := providerCalls
					mu.Unlock()
					return n == 2 && len(jobs[0].Segments) > 0 && jobs[0].Segments[0].Translation != ""
				}
			})
			_ = child.Process.Kill()
			_ = child.Wait()
			child = nil
			child = launch()
			wait(func() bool { jobs, _ := s.list("owner"); return len(jobs) == 1 && jobs[0].State == "completed" })
			jobs, _ := s.list("owner")
			if jobs[0].Attempts != 1 {
				t.Fatalf("restart spent another attempt: %d", jobs[0].Attempts)
			}
			mu.Lock()
			defer mu.Unlock()
			if phase == "recognition" && (downloads != 1 || fmt.Sprint(offsets) != "[0 600]" || len(jobs[0].Segments) != 2) {
				t.Fatalf("recognition replay downloads=%d offsets=%v segments=%d", downloads, offsets, len(jobs[0].Segments))
			}
			if phase == "download" && (downloads != 2 || workerCalls != 1) {
				t.Fatalf("partial used downloads=%d worker=%d", downloads, workerCalls)
			}
			if phase == "translation" && (downloads != 1 || workerCalls != 1 || providerCalls != 3 || fmt.Sprint(ids[1]) != "[64]" || fmt.Sprint(ids[2]) != "[64]") {
				t.Fatalf("completed batch replay downloads=%d worker=%d calls=%d ids=%v", downloads, workerCalls, providerCalls, ids)
			}
			remaining, _ := os.ReadDir(s.mediaRoot())
			if len(remaining) != 0 {
				t.Fatalf("completed media retained: %d", len(remaining))
			}
			t.Log("SIGKILL + immediate restart passed " + phase + "; provider calls=" + strconv.Itoa(providerCalls))
		})
	}
}
