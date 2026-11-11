package main

import (
	"bufio"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

// Opt-in integration: the unmodified, pinned Linux worker does real Whisper.
// Only the provider is a synthetic strict Responses SSE server. All data is disposable.
func TestPodcastRealContainerSIGKILLResume(t *testing.T) {
	if os.Getenv("PODCAST_REAL_RESUME") != "1" {
		t.Skip("requires disposable real model container and generated 660-second fixture")
	}
	audio, e := os.ReadFile(os.Getenv("PODCAST_REAL_AUDIO"))
	if e != nil {
		t.Fatal(e)
	}
	token, e := os.ReadFile(os.Getenv("PODCAST_REAL_TOKEN"))
	if e != nil {
		t.Fatal(e)
	}
	for _, cut := range []float64{600, 660} {
		t.Run(strconv.Itoa(int(cut)), func(t *testing.T) {
			root := t.TempDir()
			s, e := openPodcastStore(filepath.Join(root, "podcasts", "jobs.json"))
			if e != nil {
				t.Fatal(e)
			}
			s.create("owner", "https://example.com/generated.wav", "de", time.Now())
			os.WriteFile(filepath.Join(root, "token"), token, 0600)
			os.WriteFile(filepath.Join(root, "key"), []byte(strings.Repeat("k", 32)), 0600)
			var mu sync.Mutex
			downloads, calls, translations := 0, 0, 0
			offsets := []string{}
			source := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				mu.Lock()
				downloads++
				mu.Unlock()
				w.Header().Set("Content-Type", "audio/wav")
				w.Write(audio)
			}))
			defer source.Close()
			worker := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				req, _ := http.NewRequestWithContext(r.Context(), r.Method, os.Getenv("PODCAST_REAL_WORKER")+r.URL.Path, r.Body)
				req.Header = r.Header.Clone()
				req.ContentLength = r.ContentLength
				if r.Method == "POST" {
					mu.Lock()
					calls++
					offsets = append(offsets, r.Header.Get("X-Resume-Offset"))
					mu.Unlock()
				}
				response, e := http.DefaultClient.Do(req)
				if e != nil {
					return
				}
				defer response.Body.Close()
				w.Header().Set("Content-Type", response.Header.Get("Content-Type"))
				w.WriteHeader(response.StatusCode)
				if r.Method != "POST" {
					io.Copy(w, response.Body)
					return
				}
				mu.Lock()
				n := calls
				mu.Unlock()
				scanner := bufio.NewScanner(response.Body)
				scanner.Buffer(make([]byte, 4096), 4<<20)
				for scanner.Scan() {
					line := scanner.Bytes()
					w.Write(append(append([]byte{}, line...), '\n'))
					w.(http.Flusher).Flush()
					var cp struct {
						Type string  `json:"type"`
						End  float64 `json:"end_seconds"`
					}
					json.Unmarshal(line, &cp)
					if n == 1 && cp.Type == "checkpoint" && cp.End == cut {
						<-r.Context().Done()
						return
					}
				}
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
					Stream bool `json:"stream"`
					Store  bool `json:"store"`
					Text   struct {
						Format struct {
							Strict bool `json:"strict"`
						} `json:"format"`
					} `json:"text"`
				}
				if json.NewDecoder(r.Body).Decode(&req) != nil || !req.Stream || req.Store || !req.Text.Format.Strict {
					t.Error("provider request not strict streaming schema")
					w.WriteHeader(400)
					return
				}
				var in struct {
					Segments []podcastTranslationItem `json:"segments"`
				}
				json.Unmarshal([]byte(req.Input[0].Content), &in)
				for i := range in.Segments {
					in.Segments[i].Text = "Синтетический перевод"
				}
				b, _ := json.Marshal(in)
				mu.Lock()
				translations++
				mu.Unlock()
				w.Header().Set("Content-Type", "text/event-stream")
				io.WriteString(w, accountTranslationSSE(string(b), true, "response.completed"))
			}))
			defer provider.Close()
			launch := func() *exec.Cmd {
				c := exec.Command(os.Args[0], "-test.run=^TestPodcastResumeSubprocess$", "-test.timeout=180s")
				c.Env = append(os.Environ(), "PODCAST_RESUME_CHILD=1", "PODCAST_RESUME_ROOT="+root, "PODCAST_RESUME_WORKER="+worker.URL, "PODCAST_RESUME_PROVIDER="+provider.URL, "PODCAST_RESUME_SOURCE="+source.URL, "PODCAST_WORKER_URL=", "PROVIDER_KEY_FILE="+filepath.Join(root, "key"))
				c.Stdout = os.Stdout
				c.Stderr = os.Stderr
				if e := c.Start(); e != nil {
					t.Fatal(e)
				}
				return c
			}
			wait := func(check func() bool) {
				deadline := time.Now().Add(150 * time.Second)
				for time.Now().Before(deadline) {
					if check() {
						return
					}
					time.Sleep(20 * time.Millisecond)
				}
				t.Fatal("real container checkpoint/completion timeout")
			}
			child := launch()
			defer func() {
				if child != nil {
					child.Process.Kill()
					child.Wait()
				}
			}()
			wait(func() bool {
				jobs, _ := s.list("owner")
				return len(jobs) == 1 && jobs[0].Resume != nil && jobs[0].Resume.End == cut
			})
			jobs, _ := s.list("owner")
			if jobs[0].Resume.Complete {
				t.Fatal("partial checkpoint marked complete")
			}
			mu.Lock()
			n := translations
			mu.Unlock()
			if n != 0 {
				t.Fatal("translated partial recognition")
			}
			child.Process.Kill()
			child.Wait()
			child = nil
			// Let the real worker reap the disconnected recognizer before startup readiness.
			child = launch()
			wait(func() bool { jobs, _ := s.list("owner"); return len(jobs) == 1 && jobs[0].State == "completed" })
			jobs, _ = s.list("owner")
			j := jobs[0]
			first, last := false, false
			for _, segment := range j.Segments {
				if strings.Contains(strings.ToLower(segment.Text), "deutsch") && segment.Start < 600 {
					first = true
				}
				if strings.Contains(strings.ToLower(segment.Text), "bibliothek") && segment.Start > 649 {
					last = true
				}
				if segment.Translation == "" {
					t.Fatal("missing synthetic translation")
				}
			}
			if !first || !last || j.Attempts != 1 || !j.Resume.Complete {
				t.Fatal("real bookends/attempt/completion lost")
			}
			mu.Lock()
			defer mu.Unlock()
			if downloads != 1 || calls != 2 || strings.Join(offsets, ",") != "0,600" || translations != 1 {
				t.Fatalf("unexpected replay downloads=%d calls=%d offsets=%v translations=%d", downloads, calls, offsets, translations)
			}
			t.Logf("real worker: cut=%.0f, SIGKILL backend, offsets=%v, downloads=%d, translated=%d, segments=%d, final=completed", cut, offsets, downloads, translations, len(j.Segments))
		})
	}
}
