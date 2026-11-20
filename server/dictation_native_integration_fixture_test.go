package main

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

// Real auth, stores, playback, assessment and HTTP. Only cached PCM and the
// outbound inference adapter are synthetic. Never loads production credentials.
func TestDictationNativeIntegrationFixture(t *testing.T) {
	dir := os.Getenv("DICTATION_NATIVE_INTEGRATION")
	if dir == "" {
		t.Skip("explicit local native fixture only")
	}
	f := newAssessmentFixture(t)
	f.reply = func(r *http.Request) (string, error) {
		var body struct {
			Input []struct {
				Content string `json:"content"`
			} `json:"input"`
		}
		if e := json.NewDecoder(r.Body).Decode(&body); e != nil {
			return "", e
		}
		if len(body.Input) != 1 {
			return "", errors.New("synthetic input shape")
		}
		var input struct {
			Answer    string             `json:"answer"`
			Alignment dictationAlignment `json:"alignment"`
		}
		if e := json.Unmarshal([]byte(body.Input[0].Content), &input); e != nil {
			return "", e
		}
		delay := 3 * time.Second
		// UI scrolling must observe a genuine pending response before completion.
		// Keep the HTTP-only fixture fast unless the UI runner opts into delay.
		if strings.Contains(input.Answer, "Cancel") || os.Getenv("DICTATION_NATIVE_INTEGRATION_SLOW_PROVIDER") == "1" {
			delay = 8 * time.Second
		}
		select {
		case <-r.Context().Done():
			return "", r.Context().Err()
		case <-time.After(delay):
		}
		if strings.Contains(input.Answer, "Fehler") {
			return "", errors.New("synthetic inference failure")
		}
		result := dictationAssessmentResult{Notes: []dictationAssessmentNote{}}
		for _, s := range input.Alignment.Spans {
			if s.Kind != "equal" && s.Kind != "unattempted" {
				result.Notes = append(result.Notes, dictationAssessmentNote{s.ID, "grammar", s.Original, s.Written, "Synthetic explanation for native testing. The source remains unchanged."})
				break
			}
		}
		b, _ := json.Marshal(result)
		return accountTranslationSSE(string(b), true, "response.completed"), nil
	}
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		bits := strings.Split(strings.TrimPrefix(r.URL.Path, "/v1/learning/dictations/"), "/")
		if r.Method == "POST" && len(bits) == 3 && bits[1] == "audio" {
			session, e := f.cfg.auth.store.lookup(bearerSession(r), time.Now())
			asset, ae := strconv.Atoi(bits[2])
			if e == nil && ae == nil {
				e = f.cfg.dictationTransaction(session.UserID, false, func(d *dictationData) error {
					v := dictationFind(d, bits[0])
					if v == nil {
						return errDictationMissing
					}
					for _, p := range v.Plan {
						if p.Asset == asset {
							path := dictationAssetPath(f.cfg.dictationRoot(session.UserID), v.ID, asset)
							if e := os.MkdirAll(filepath.Dir(path), 0700); e != nil {
								return e
							}
							wav := playbackSilentWAV()
							if strings.HasPrefix(v.Title, "Global") {
								wav = append(wav, make([]byte, 29*16000)...)
								binary.LittleEndian.PutUint32(wav[4:], uint32(len(wav)-8))
								binary.LittleEndian.PutUint32(wav[40:], uint32(len(wav)-44))
							}
							if strings.HasPrefix(v.Title, "Timeline") {
								wav = append(wav, make([]byte, 4*16000)...)
								binary.LittleEndian.PutUint32(wav[4:], uint32(len(wav)-8))
								binary.LittleEndian.PutUint32(wav[40:], uint32(len(wav)-44))
							}
							return os.WriteFile(path, wav, 0600)
						}
					}
					return errDictationMissing
				})
				if e != nil {
					http.Error(w, "synthetic media unavailable", 404)
					return
				}
			}
		}
		f.h.ServeHTTP(w, r)
	})
	address := os.Getenv("DICTATION_NATIVE_INTEGRATION_ADDR")
	if address == "" {
		address = "127.0.0.1:0"
	}
	listener, e := net.Listen("tcp", address)
	if e != nil {
		t.Fatal(e)
	}
	srv := &http.Server{Handler: handler, ReadHeaderTimeout: 5 * time.Second}
	defer srv.Close()
	go func() { _ = srv.Serve(listener) }()
	if e = os.MkdirAll(dir, 0700); e != nil {
		t.Fatal(e)
	}
	b, _ := json.Marshal(map[string]string{"url": "http://" + listener.Addr().String(), "native": f.token, "owner": f.owner, "store": filepath.Dir(f.cfg.historyPath)})
	if e = os.WriteFile(filepath.Join(dir, "fixture.json"), b, 0600); e != nil {
		t.Fatal(e)
	}
	deadline := time.Now().Add(45 * time.Minute)
	for time.Now().Before(deadline) {
		if _, e = os.Stat(filepath.Join(dir, "done")); e == nil {
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatal("native fixture lifetime exceeded")
}
