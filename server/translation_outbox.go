package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
)

var translationRequestKey = regexp.MustCompile(`^[A-Za-z0-9_-]{16,128}$`)

type translationReceipt struct {
	Digest string             `json:"digest"`
	Result *translationRecord `json:"result,omitempty"`
}
type translationClaim struct {
	path     string
	digest   string
	recordID string
}

// Pending survives crashes. It is never treated as permission to spend again.
// The server cannot know whether an external provider completed before a crash.
func (cfg *serverConfig) claimTranslation(w http.ResponseWriter, r *http.Request, owner string, input translationInput, history *historyStore) (*translationClaim, bool) {
	key := r.Header.Get("Idempotency-Key")
	if key == "" {
		return nil, true
	}
	if !translationRequestKey.MatchString(key) {
		writeError(w, 400, "invalid idempotency key")
		return nil, false
	}
	c := &translationClaim{path: filepath.Join(cfg.provider.dir, "translation-receipts", sessionHash(owner), sessionHash(key)+".json"), digest: learningDigest(input)}
	c.recordID = "outbox-" + sessionHash(owner+"\x00"+key)
	var prior *translationReceipt
	err := (&historyStore{path: c.path}).locked(func() error {
		b, e := os.ReadFile(c.path)
		if e == nil {
			var v translationReceipt
			if e = json.Unmarshal(b, &v); e != nil {
				return e
			}
			prior = &v
			return nil
		}
		if !errors.Is(e, os.ErrNotExist) {
			return e
		}
		// If only the receipt was lost, history still proves this request was
		// spent. Recover its digest too so changed input cannot spend again.
		if e := history.locked(func() error {
			items, e := history.read()
			if e != nil {
				return e
			}
			for _, item := range items {
				if item.ID == c.recordID {
					copy := item
					prior = &translationReceipt{Digest: learningDigest(item.translationInput), Result: &copy}
					break
				}
			}
			return nil
		}); e != nil {
			return e
		}
		if prior != nil {
			return learningAtomicJSON(c.path, prior)
		}
		return learningAtomicJSON(c.path, translationReceipt{Digest: c.digest})
	})
	if err != nil {
		writeError(w, 503, "request storage unavailable")
		return nil, false
	}
	if prior == nil {
		return c, true
	}
	if prior.Digest != c.digest {
		writeError(w, 409, "request snapshot conflict")
		return nil, false
	}
	if prior.Result == nil {
		var recovered *translationRecord
		err := history.locked(func() error {
			items, e := history.read()
			if e != nil {
				return e
			}
			for _, item := range items {
				if item.ID == c.recordID && learningDigest(item.translationInput) == c.digest {
					copy := item
					recovered = &copy
					break
				}
			}
			return nil
		})
		if err != nil {
			writeError(w, 503, "history unavailable")
			return nil, false
		}
		if recovered != nil {
			if err := c.complete(*recovered); err != nil {
				writeError(w, 503, "receipt unavailable")
				return nil, false
			}
			writeJSON(w, 201, recovered)
			return nil, false
		}
		writeError(w, 409, "translation outcome uncertain; do not automatically repeat")
		return nil, false
	}
	var exists bool
	if err := history.locked(func() error {
		items, err := history.read()
		if err != nil {
			return err
		}
		for _, item := range items {
			if item.ID == c.recordID && learningDigest(item.translationInput) == c.digest {
				exists = true
				break
			}
		}
		return nil
	}); err != nil {
		writeError(w, 503, "history unavailable")
		return nil, false
	}
	if !exists {
		writeError(w, 409, "saved translation was removed")
		return nil, false
	}
	writeJSON(w, 201, prior.Result)
	return nil, false
}
func (c *translationClaim) abandon() {
	if c != nil {
		_ = (&historyStore{path: c.path}).locked(func() error { return os.Remove(c.path) })
	}
}
func (c *translationClaim) complete(record translationRecord) error {
	if c == nil {
		return nil
	}
	return (&historyStore{path: c.path}).locked(func() error { return learningAtomicJSON(c.path, translationReceipt{Digest: c.digest, Result: &record}) })
}
func (s *historyStore) appendOnce(record translationRecord) error {
	return s.locked(func() error {
		items, err := s.read()
		if err != nil {
			return err
		}
		for _, item := range items {
			if item.ID == record.ID {
				if learningDigest(item.translationInput) != learningDigest(record.translationInput) {
					return errors.New("translation snapshot conflict")
				}
				return nil
			}
		}
		return s.write(append(items, record))
	})
}
