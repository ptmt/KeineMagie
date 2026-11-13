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

// Retain small replay tombstones, never an indefinitely retained copy of text.
// There is no TTL: deleting spent keys would authorize duplicate provider work.
const translationReceiptLimit = 4096

var errTranslationReceiptCapacity = errors.New("translation receipt capacity reached")

type translationReceipt struct {
	Digest    string `json:"digest"`
	Completed bool   `json:"completed,omitempty"`
}
type translationClaim struct {
	path     string
	digest   string
	recordID string
}

func (c *translationClaim) locked(fn func() error) error {
	// One stable owner sidecar also bounds lock-file growth for rejected keys.
	return (&historyStore{path: filepath.Join(filepath.Dir(c.path), "admission")}).locked(fn)
}

// Pending survives crashes. It is never permission to spend again.
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
	var recovered *translationRecord
	err := c.locked(func() error {
		b, e := os.ReadFile(c.path)
		if e == nil {
			var v translationReceipt
			if e = json.Unmarshal(b, &v); e != nil {
				return e
			}
			prior = &v
		} else if !errors.Is(e, os.ErrNotExist) {
			return e
		}
		// Authoritative history supplies the current record, including later edits.
		if e := history.locked(func() error {
			items, e := history.read()
			if e != nil {
				return e
			}
			for _, item := range items {
				if item.ID == c.recordID {
					copy := item
					recovered = &copy
					break
				}
			}
			return nil
		}); e != nil {
			return e
		}
		if prior != nil {
			return nil
		}
		if recovered != nil {
			prior = &translationReceipt{Digest: learningDigest(recovered.translationInput), Completed: true}
			return learningAtomicJSON(c.path, prior)
		}
		entries, e := os.ReadDir(filepath.Dir(c.path))
		if e != nil {
			return e
		}
		count := 0
		for _, entry := range entries {
			if filepath.Ext(entry.Name()) == ".json" {
				count++
			}
		}
		if count >= translationReceiptLimit {
			return errTranslationReceiptCapacity
		}
		return learningAtomicJSON(c.path, translationReceipt{Digest: c.digest})
	})
	if errors.Is(err, errTranslationReceiptCapacity) {
		writeError(w, 429, "translation receipt capacity reached; existing requests can still be checked")
		return nil, false
	}
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
	if recovered != nil && learningDigest(recovered.translationInput) == c.digest {
		if err := c.complete(*recovered); err != nil {
			writeError(w, 503, "receipt unavailable")
			return nil, false
		}
		writeJSON(w, 201, recovered)
		return nil, false
	}
	if prior.Completed {
		writeError(w, 409, "saved translation was removed")
	} else {
		writeError(w, 409, "translation outcome uncertain; do not automatically repeat")
	}
	return nil, false
}
func (c *translationClaim) abandon() {
	if c != nil {
		_ = c.locked(func() error { return os.Remove(c.path) })
	}
}
func (c *translationClaim) complete(record translationRecord) error {
	if c == nil {
		return nil
	}
	return c.locked(func() error { return learningAtomicJSON(c.path, translationReceipt{Digest: c.digest, Completed: true}) })
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
