package main

import (
	"context"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
	"time"
)

func dictationTTSAvailable() bool { _, err := dictationLoadOpenAI(); return err == nil }
func (cfg *serverConfig) dictationAudio(w http.ResponseWriter, r *http.Request, owner, id string, parts []string) {
	if len(parts) != 1 {
		writeError(w, 404, "not found")
		return
	}
	index, e := strconv.Atoi(parts[0])
	if e != nil || index < 0 || index > 120 || strconv.Itoa(index) != parts[0] {
		writeError(w, 400, "invalid audio index")
		return
	}
	var text string
	e = cfg.dictationTransaction(owner, false, func(d *dictationData) error {
		v := dictationFind(d, id)
		if v == nil {
			return errDictationMissing
		}
		for _, s := range v.Plan {
			if s.Asset == index {
				text = s.Text
				return nil
			}
		}
		return errDictationMissing
	})
	if e != nil {
		dictationError(w, e)
		return
	}
	path := dictationAssetPath(cfg.dictationRoot(owner), id, index)
	if r.Method == "GET" || r.Method == "HEAD" {
		f, e := os.Open(path)
		if e != nil {
			writeError(w, 404, "Audio not prepared. Tap Prepare audio.")
			return
		}
		defer f.Close()
		info, e := f.Stat()
		if e != nil {
			dictationError(w, e)
			return
		}
		w.Header().Set("Content-Type", "audio/wav")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		http.ServeContent(w, r, "audio.wav", info.ModTime(), f)
		return
	}
	if r.Method != "POST" {
		writeError(w, 405, "method not allowed")
		return
	}
	var in struct{}
	if !learningDecode(w, r, &in) {
		return
	}
	// Nonblocking global cross-process admission: one engine process at a time.
	root := filepath.Join(filepath.Dir(cfg.historyPath), "dictations")
	if e = os.MkdirAll(root, 0700); e != nil {
		dictationError(w, e)
		return
	}
	lock, e := os.OpenFile(filepath.Join(root, "generation.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if e != nil {
		dictationError(w, e)
		return
	}
	defer lock.Close()
	if e = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); e != nil {
		writeJSON(w, 429, map[string]any{"error": "Audio engine busy. Retry shortly.", "code": "speech_engine_busy"})
		return
	}
	defer syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)
	// Unrecognized accounting blocks paid generation, while cached assets remain
	// usable without changing any accounting evidence.
	recoveryErr := dictationRecoverPrepared(root)
	if _, e = os.Stat(path); e == nil {
		e = cfg.dictationWrite(r, owner, func(d *dictationData) error {
			if err := r.Context().Err(); err != nil {
				return err
			}
			v := dictationFind(d, id)
			if v == nil {
				return errDictationMissing
			}
			for _, n := range v.Ready {
				if n == index {
					return nil
				}
			}
			v.Ready = append(v.Ready, index)
			return nil
		})
		if e != nil {
			dictationError(w, e)
			return
		}
		writeJSON(w, 200, map[string]any{"ready": true})
		return
	}
	if recoveryErr != nil {
		dictationError(w, recoveryErr)
		return
	}
	speechConfig, configErr := dictationLoadOpenAI()
	if configErr != nil {
		writeError(w, 503, "OpenAI speech is not configured with an approved budget. No fallback.")
		return
	}
	ticket, e := dictationPrepareAttempt(root, owner, id+"/"+strconv.Itoa(index))
	if e != nil {
		dictationError(w, e)
		return
	}
	defer dictationReleasePrepared(root, ticket)
	speechConfig.beforeAttempt = func(ctx context.Context) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		return cfg.dictationAuthorized(r, owner, false, func(d *dictationData) error {
			if err := ctx.Err(); err != nil {
				return err
			}
			if dictationFind(d, id) == nil {
				return errDictationMissing
			}
			legacyOwner := 0
			if d.Day == time.Now().UTC().Format("2006-01-02") {
				legacyOwner = d.Generations
			}
			return dictationMarkAttempted(root, ticket, speechConfig, text, owner, legacyOwner)
		})
	}
	speechConfig.usage = func(u dictationSpeechUsage) error { return dictationRecordUsage(root, ticket, u) }
	speechConfig.completedUsage = func(id string, u dictationSpeechUsage) error {
		return dictationRecordCompletedUsage(root, ticket, id, u)
	}
	synthesize := cfg.dictationSpeech
	if synthesize == nil {
		synthesize = func(ctx context.Context, c dictationOpenAIConfig, text string) ([]byte, error) {
			return dictationRealtime(ctx, c, text, "wss://api.openai.com/v1/realtime?model="+url.QueryEscape(c.model))
		}
	}
	audio, e := synthesize(r.Context(), speechConfig, text)
	if e != nil {
		dictationError(w, dictationAttemptFailure(root, ticket, e))
		return
	}
	// Revalidate identity and cancellation at publication, including after logout.
	e = cfg.dictationWrite(r, owner, func(d *dictationData) error {
		if e := r.Context().Err(); e != nil {
			return e
		}
		v := dictationFind(d, id)
		if v == nil {
			return errDictationMissing
		}
		if e := os.MkdirAll(filepath.Dir(path), 0700); e != nil {
			return e
		}
		f, e := os.CreateTemp(filepath.Dir(path), ".audio-*")
		if e != nil {
			return e
		}
		defer os.Remove(f.Name())
		defer f.Close()
		if _, e = f.Write(audio); e != nil {
			return e
		}
		if e = f.Sync(); e != nil {
			return e
		}
		if e = f.Close(); e != nil {
			return e
		}
		if e = os.Rename(f.Name(), path); e != nil {
			return e
		}
		dir, e := os.Open(filepath.Dir(path))
		if e != nil {
			return e
		}
		e = dir.Sync()
		dir.Close()
		if e != nil {
			return e
		}
		for _, n := range v.Ready {
			if n == index {
				return nil
			}
		}
		v.Ready = append(v.Ready, index)
		return nil
	})
	if e != nil {
		dictationError(w, dictationAttemptFailure(root, ticket, e))
		return
	}
	writeJSON(w, 200, map[string]any{"ready": true})
}
