package main

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

// Explicit in-process HTTP bridge for browser fixtures. No sockets, provider
// transport or production stores. WAVs are synthetic silence, not voice evidence.
type playbackBridgeIdentity struct {
	Owner   string `json:"owner"`
	Token   string `json:"token"`
	Browser string `json:"browser"`
	CSRF    string `json:"csrf_token"`
}
type playbackBridgeRequest struct {
	Method  string            `json:"method"`
	Path    string            `json:"path"`
	Body    string            `json:"body"`
	Headers map[string]string `json:"headers"`
}
type playbackBridgeResponse struct {
	Status  int               `json:"status"`
	Body    []byte            `json:"body"`
	Headers map[string]string `json:"headers"`
}

func TestDictationPlaybackHTTPBridge(t *testing.T) {
	root := os.Getenv("DICTATION_PLAYBACK_BRIDGE")
	if root == "" {
		t.Skip("explicit synthetic stdio fixture only")
	}
	t.Setenv("WEB_ORIGIN", "https://dictation.test")
	cfg := &serverConfig{authPath: filepath.Join(root, "auth.json"), historyPath: filepath.Join(root, "history.json")}
	h, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	bootPath := filepath.Join(root, "fixture.json")
	var identity playbackBridgeIdentity
	if b, e := os.ReadFile(bootPath); e == nil {
		if e = json.Unmarshal(b, &identity); e != nil {
			t.Fatal(e)
		}
	} else {
		token, s, e := cfg.auth.store.create("synthetic-playback-fixture", time.Now())
		if e != nil {
			t.Fatal(e)
		}
		browser, e := cfg.auth.store.createBrowser(token, s.UserID, time.Now())
		if e != nil {
			t.Fatal(e)
		}
		identity = playbackBridgeIdentity{s.UserID, token, browser, browserCSRF(browser)}
		if e = learningAtomicJSON(bootPath, identity); e != nil {
			t.Fatal(e)
		}
	}
	encoder := json.NewEncoder(os.Stdout)
	fmt.Print("PLAYBACK_BOOT ")
	encoder.Encode(identity)
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), 1<<20)
	for scanner.Scan() {
		var in playbackBridgeRequest
		if e = json.Unmarshal(scanner.Bytes(), &in); e != nil {
			t.Fatal(e)
		}
		r := httptest.NewRequest(in.Method, "https://dictation.test"+in.Path, strings.NewReader(in.Body))
		for k, v := range in.Headers {
			r.Header.Set(k, v)
		}
		// Explicit Prepare only. The real handler still owns authentication, Ready,
		// reservations, HTTP Range, CSRF and durable publication metadata.
		session, authErr := cfg.auth.store.lookup(bearerSession(r), time.Now())
		if cookie := cookieValue(r, browserCookie); cookie != "" && r.Header.Get("Origin") == "https://dictation.test" && r.Header.Get("X-CSRF-Token") == browserCSRF(cookie) {
			session, authErr = cfg.auth.store.lookup(cookie, time.Now())
		}
		bits := strings.Split(strings.TrimPrefix(r.URL.Path, "/v1/learning/dictations/"), "/")
		if in.Method == "POST" && len(bits) == 3 && bits[1] == "audio" && authErr == nil {
			index, err := strconv.Atoi(bits[2])
			if err == nil {
				e = cfg.dictationTransaction(session.UserID, false, func(d *dictationData) error {
					v := dictationFind(d, bits[0])
					if v == nil {
						return errDictationMissing
					}
					for _, s := range v.Plan {
						if s.Asset == index {
							path := dictationAssetPath(cfg.dictationRoot(session.UserID), v.ID, index)
							if e := os.MkdirAll(filepath.Dir(path), 0700); e != nil {
								return e
							}
							return os.WriteFile(path, playbackSilentWAV(), 0600)
						}
					}
					return errDictationMissing
				})
				if e != nil {
					t.Fatal(e)
				}
			}
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		headers := map[string]string{}
		for k, v := range w.Header() {
			headers[k] = strings.Join(v, ", ")
		}
		encoder.Encode(playbackBridgeResponse{w.Code, w.Body.Bytes(), headers})
	}
	if e = scanner.Err(); e != nil {
		t.Fatal(e)
	}
}
func playbackSilentWAV() []byte {
	b := make([]byte, 44+16000)
	copy(b, "RIFF")
	binary.LittleEndian.PutUint32(b[4:], uint32(len(b)-8))
	copy(b[8:], "WAVEfmt ")
	binary.LittleEndian.PutUint32(b[16:], 16)
	binary.LittleEndian.PutUint16(b[20:], 1)
	binary.LittleEndian.PutUint16(b[22:], 1)
	binary.LittleEndian.PutUint32(b[24:], 8000)
	binary.LittleEndian.PutUint32(b[28:], 16000)
	binary.LittleEndian.PutUint16(b[32:], 2)
	binary.LittleEndian.PutUint16(b[34:], 16)
	copy(b[36:], "data")
	binary.LittleEndian.PutUint32(b[40:], 16000)
	return b
}
func TestDictationPlaybackSIGKILLPersistence(t *testing.T) {
	root := t.TempDir()
	exe, e := os.Executable()
	if e != nil {
		t.Fatal(e)
	}
	cmd := exec.Command(exe, "-test.run=^TestDictationPlaybackHTTPBridge$")
	cmd.Env = append(os.Environ(), "DICTATION_PLAYBACK_BRIDGE="+root)
	stdin, e := cmd.StdinPipe()
	if e != nil {
		t.Fatal(e)
	}
	stdout, e := cmd.StdoutPipe()
	if e != nil {
		t.Fatal(e)
	}
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if e = cmd.Start(); e != nil {
		t.Fatal(e)
	}
	defer func() { cmd.Process.Kill(); cmd.Wait() }()
	scanner := bufio.NewScanner(stdout)
	if !scanner.Scan() || !strings.HasPrefix(scanner.Text(), "PLAYBACK_BOOT ") {
		t.Fatal("bridge failed", scanner.Text(), stderr.String())
	}
	var identity playbackBridgeIdentity
	json.Unmarshal([]byte(strings.TrimPrefix(scanner.Text(), "PLAYBACK_BOOT ")), &identity)
	encoder := json.NewEncoder(stdin)
	call := func(method, path, body string) {
		t.Helper()
		encoder.Encode(playbackBridgeRequest{method, "/v1/learning/dictations" + path, body, map[string]string{"Authorization": "Bearer " + identity.Token}})
		if !scanner.Scan() {
			t.Fatal("no response", stderr.String())
		}
		var out playbackBridgeResponse
		if e = json.Unmarshal(scanner.Bytes(), &out); e != nil || out.Status != 200 {
			t.Fatal("bridge response", scanner.Text(), e)
		}
	}
	call("POST", "", `{"id":"killed","title":"Synthetic","text":"Hallo.","language":"de","playback_policy_version":1}`)
	call("POST", "/killed/audio/0", `{}`)
	call("POST", "/killed/playback", playbackBody("durable", "tab", "start", 0, 0))
	if e = cmd.Process.Kill(); e != nil {
		t.Fatal(e)
	}
	cmd.Wait()
	cfg := &serverConfig{authPath: filepath.Join(root, "auth.json"), historyPath: filepath.Join(root, "history.json")}
	h, e := newHandler(cfg)
	if e != nil {
		t.Fatal(e)
	}
	r := httptest.NewRequest("GET", "/v1/learning/dictations/killed", nil)
	r.Header.Set("Authorization", "Bearer "+identity.Token)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	var record dictationRecord
	if e = json.Unmarshal(w.Body.Bytes(), &record); e != nil || w.Code != 200 || record.Playback.WholeStarts != 1 || record.Playback.Active.ID != "durable" {
		t.Fatal("SIGKILL lost reservation", w.Code, w.Body, e)
	}
}
