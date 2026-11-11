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

// Ordinary translations retain their existing charge-on-admission semantics.
func (p *providerService) beginTranslation(user string, now time.Time) (func(), error) {
	consume, release, err := p.reserveTranslationPlan(user, now, 1)
	if err != nil {
		return nil, err
	}
	if err = consume(now); err != nil {
		release()
		return nil, err
	}
	return release, nil
}

// The cross-process account flock reserves capacity for the entire remaining
// plan without billing unsent work. Hold it until completion/cancellation. A
// process crash releases the reservation automatically; only durably consumed
// attempts survive. No compensating refunds or stale persisted holds are needed.
func (p *providerService) reserveTranslationPlan(user string, now time.Time, attempts int) (func(time.Time) error, func(), error) {
	if attempts < 1 || attempts > podcastMaxSegments {
		return nil, nil, errors.New("invalid translation reservation")
	}
	limit, err := strconv.Atoi(getenv("TRANSLATION_DAILY_ATTEMPTS", "100"))
	if err != nil || limit < 1 || limit > 10000 {
		return nil, nil, errors.New("quota unavailable")
	}
	dir := filepath.Join(p.dir, "quotas")
	if err = os.MkdirAll(dir, 0700); err != nil {
		return nil, nil, err
	}
	path := filepath.Join(dir, sessionHash(user)+".json")
	active, err := os.OpenFile(path+".active", os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return nil, nil, err
	}
	release := func() { _ = syscall.Flock(int(active.Fd()), syscall.LOCK_UN); _ = active.Close() }
	if err = syscall.Flock(int(active.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		active.Close()
		return nil, nil, errors.New("translation already active")
	}
	lock := &historyStore{path: path}
	remaining := attempts
	update := func(at time.Time, charge bool) error {
		return lock.locked(func() error {
			var q dailyTranslationQuota
			b, e := os.ReadFile(path)
			if e != nil && !errors.Is(e, os.ErrNotExist) {
				return e
			}
			if e == nil {
				if e = json.Unmarshal(b, &q); e != nil {
					return e
				}
			}
			day := at.UTC().Format("2006-01-02")
			if q.Day != day {
				q = dailyTranslationQuota{Day: day}
			}
			if q.Attempts < 0 || remaining < 1 || remaining > limit-q.Attempts {
				return errors.New("daily quota exceeded")
			}
			if !charge {
				return nil
			}
			q.Attempts++
			b, e = json.Marshal(q)
			if e != nil {
				return e
			}
			f, e := os.CreateTemp(dir, ".quota-*")
			if e != nil {
				return e
			}
			defer os.Remove(f.Name())
			defer f.Close()
			if _, e = f.Write(b); e != nil {
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
			directory, e := os.Open(dir)
			if e != nil {
				return e
			}
			defer directory.Close()
			if e = directory.Sync(); e != nil {
				return e
			}
			remaining--
			return nil
		})
	}
	if err = update(now, false); err != nil {
		release()
		return nil, nil, err
	}
	return func(at time.Time) error { return update(at, true) }, release, nil
}
