package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

// Profiles never enter provider configuration. Only a submitted translation's
// immutable instructions snapshot uses their untrusted text.
type translationProfile struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	Instruction string `json:"instruction"`
	Revision    int64  `json:"revision"`
	Deleted     bool   `json:"deleted"`
}
type translationProfiles struct {
	Revision int64                `json:"revision"`
	Items    []translationProfile `json:"items"`
	Receipts map[string]string    `json:"receipts,omitempty"`
}
type translationProfileOperation struct {
	OperationID  string `json:"operation_id"`
	ID           string `json:"id"`
	BaseRevision int64  `json:"base_revision"`
	Title        string `json:"title"`
	Instruction  string `json:"instruction"`
}

var profileIdentifier = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$`)
var errProfileConflict = errors.New("profile changed; keep the draft and reload or save as a new profile")
var errProfileCapacity = errors.New("profile storage limit")

// encoding/json replaces invalid UTF-8 and unpaired UTF-16 escapes. Reject
// those before decoding so imported identity and stored content stay exact.
func profileLosslessJSON(b []byte) bool {
	if !utf8.Valid(b) || !json.Valid(b) {
		return false
	}
	for i := 0; i < len(b); i++ {
		if b[i] != '\\' {
			continue
		}
		i++
		if b[i] != 'u' {
			continue
		}
		code, _ := strconv.ParseUint(string(b[i+1:i+5]), 16, 16)
		i += 4
		if code >= 0xdc00 && code <= 0xdfff {
			return false
		}
		if code >= 0xd800 && code <= 0xdbff {
			if i+6 >= len(b) || b[i+1] != '\\' || b[i+2] != 'u' {
				return false
			}
			low, err := strconv.ParseUint(string(b[i+3:i+7]), 16, 16)
			if err != nil || low < 0xdc00 || low > 0xdfff {
				return false
			}
			i += 6
		}
	}
	return true
}

func (cfg *serverConfig) profileLock(owner string) *historyStore {
	return &historyStore{path: filepath.Join(filepath.Dir(cfg.historyPath), "translation-profiles", sessionHash(owner)+".json")}
}
func (cfg *serverConfig) handleTranslationProfiles(w http.ResponseWriter, r *http.Request) {
	owner, ok := cfg.provider.owner(w, r)
	if !ok {
		return
	}
	if expected := r.Header.Get("X-Translation-Owner"); expected != "" && expected != owner {
		writeError(w, 403, "translation owner changed")
		return
	}
	method := r.Method
	if method != "GET" && method != "PUT" && method != "PATCH" && method != "DELETE" {
		writeError(w, 405, "method not allowed")
		return
	}
	var in translationProfileOperation
	if method != "GET" {
		_ = http.NewResponseController(w).SetReadDeadline(time.Now().Add(10 * time.Second))
		defer http.NewResponseController(w).SetReadDeadline(time.Time{})
		raw, readErr := io.ReadAll(http.MaxBytesReader(w, r.Body, 16384))
		_ = r.Body.Close()
		if readErr != nil || !profileLosslessJSON(raw) {
			writeError(w, 400, "invalid JSON body")
			return
		}
		r.Body = io.NopCloser(bytes.NewReader(raw))
		if !learningDecode(w, r, &in) {
			return
		}
		if !profileIdentifier.MatchString(in.ID) || !profileIdentifier.MatchString(in.OperationID) || in.BaseRevision < 0 || in.ID == "friendly" || in.ID == "formal" || in.ID == "normal" {
			writeError(w, 400, "invalid profile identity")
			return
		}
		if method != "DELETE" && (!utf8.ValidString(in.Title) || !utf8.ValidString(in.Instruction) || strings.TrimSpace(in.Title) == "" || runeCount(in.Title) > 60 || strings.TrimSpace(in.Instruction) == "" || runeCount(in.Instruction) > 1000) {
			writeError(w, 400, "expected title (1–60 Unicode scalars) and instruction (1–1000 Unicode scalars)")
			return
		}
		if method == "DELETE" && (in.Title != "" || in.Instruction != "") {
			writeError(w, 400, "delete must not contain text")
			return
		}
	}
	var out translationProfiles
	// Same lock order for every read/write: auth -> owner. Logout cannot race an
	// append, and a queued read cannot publish private content after revocation.
	err := cfg.auth.store.lock.locked(func() error {
		auth, e := cfg.auth.store.read()
		if e != nil {
			return e
		}
		s := auth.Sessions[sessionHash(bearerSession(r))]
		if s.UserID != owner || !cfg.auth.now().Before(s.Expires) {
			return errCoachUnauthorized
		}
		if r.Context().Err() != nil {
			return r.Context().Err()
		}
		lock := cfg.profileLock(owner)
		return lock.locked(func() error {
			d := translationProfiles{Items: []translationProfile{}, Receipts: map[string]string{}}
			b, e := os.ReadFile(lock.path)
			if e == nil {
				if len(b) > 32<<20 {
					return errProfileCapacity
				}
				if e = json.Unmarshal(b, &d); e != nil {
					return e
				}
				if d.Items == nil || d.Receipts == nil {
					return errors.New("invalid profile store")
				}
			} else if !errors.Is(e, os.ErrNotExist) {
				return e
			}
			if method != "GET" {
				digest := learningDigest(struct {
					Method string
					Input  translationProfileOperation
				}{method, in})
				if previous, exists := d.Receipts[in.OperationID]; exists {
					if previous != digest {
						return errProfileConflict
					}
				} else {
					index := -1
					live := 0
					for i, v := range d.Items {
						if v.ID == in.ID {
							index = i
						}
						if !v.Deleted {
							live++
						}
					}
					if index < 0 {
						if method != "PUT" || in.BaseRevision != 0 {
							return errProfileConflict
						}
						if live >= 50 || len(d.Items) >= 10000 {
							return errProfileCapacity
						}
					} else if method == "PUT" || d.Items[index].Deleted || d.Items[index].Revision != in.BaseRevision {
						return errProfileConflict
					}
					if len(d.Receipts) >= 100000 {
						return errProfileCapacity
					}
					d.Revision++
					item := translationProfile{ID: in.ID, Title: in.Title, Instruction: in.Instruction, Revision: d.Revision, Deleted: method == "DELETE"}
					if index < 0 {
						d.Items = append(d.Items, item)
					} else {
						d.Items[index] = item
					}
					d.Receipts[in.OperationID] = digest
					if e = learningAtomicJSON(lock.path, d); e != nil {
						return e
					}
				}
			}
			out = d
			out.Receipts = nil
			return nil
		})
	})
	if errors.Is(err, errCoachUnauthorized) {
		writeError(w, 401, "authentication failed")
		return
	}
	if errors.Is(err, errProfileConflict) {
		writeError(w, 409, err.Error())
		return
	}
	if errors.Is(err, errProfileCapacity) {
		writeError(w, 422, err.Error())
		return
	}
	if err != nil {
		writeError(w, 503, "profile store unavailable")
		return
	}
	writeJSON(w, 200, out)
}
