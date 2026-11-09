package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
	"time"
)

type dailyTranslationQuota struct {
	Day      string `json:"day"`
	Attempts int    `json:"attempts"`
}

// Cross-process nonblocking flock provides one active request per account. Daily
// attempts are persisted before upstream work, including failed attempts.
func (p *providerService) beginTranslation(user string, now time.Time) (func(), error) {
	limit, e := strconv.Atoi(getenv("TRANSLATION_DAILY_ATTEMPTS", "100"))
	if e != nil || limit < 1 || limit > 10000 {
		return nil, errors.New("quota unavailable")
	}
	dir := filepath.Join(p.dir, "quotas")
	if e = os.MkdirAll(dir, 0700); e != nil {
		return nil, e
	}
	path := filepath.Join(dir, sessionHash(user)+".json")
	active, e := os.OpenFile(path+".active", os.O_CREATE|os.O_RDWR, 0600)
	if e != nil {
		return nil, e
	}
	release := func() { _ = syscall.Flock(int(active.Fd()), syscall.LOCK_UN); _ = active.Close() }
	if e = syscall.Flock(int(active.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); e != nil {
		active.Close()
		return nil, errors.New("translation already active")
	}
	lock := &historyStore{path: path}
	e = lock.locked(func() error {
		var q dailyTranslationQuota
		b, err := os.ReadFile(path)
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
		if err == nil {
			if err = json.Unmarshal(b, &q); err != nil {
				return err
			}
		}
		day := now.UTC().Format("2006-01-02")
		if q.Day != day {
			q = dailyTranslationQuota{Day: day}
		}
		if q.Attempts >= limit {
			return errors.New("daily quota exceeded")
		}
		q.Attempts++
		b, err = json.Marshal(q)
		if err != nil {
			return err
		}
		f, err := os.CreateTemp(dir, ".quota-*")
		if err != nil {
			return err
		}
		defer os.Remove(f.Name())
		defer f.Close()
		if _, err = f.Write(b); err != nil {
			return err
		}
		if err = f.Sync(); err != nil {
			return err
		}
		if err = f.Close(); err != nil {
			return err
		}
		if err = os.Rename(f.Name(), path); err != nil {
			return err
		}
		directory, err := os.Open(dir)
		if err != nil {
			return err
		}
		defer directory.Close()
		return directory.Sync()
	})
	if e != nil {
		release()
		return nil, e
	}
	return release, nil
}
