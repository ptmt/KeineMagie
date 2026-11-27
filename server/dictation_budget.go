package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"time"
)

type dictationPaidBudget struct {
	Day        string `json:"day"`
	Requests   int    `json:"requests"`
	Characters int    `json:"characters"`
	Seconds    int    `json:"reserved_seconds"`
}

var errDictationBudget = errors.New("speech application limit reached")

// Legacy daily reservation writer, retained for compatibility and offline tests.
// Live audio now commits daily quota together with per-attempt intent in the
// monthly ledger; it includes these legacy counters without rewriting them.
func dictationReservePaid(root string, c dictationOpenAIConfig, text string) error {
	n := runeCount(text)
	if n < 1 || n > c.chars {
		return errDictationBudget
	}
	store := &historyStore{path: filepath.Join(root, "paid-budget.json")}
	return store.locked(func() error {
		d := dictationPaidBudget{}
		b, e := os.ReadFile(store.path)
		if e == nil {
			if len(b) > 4096 {
				return errDictationBudget
			}
			if e = json.Unmarshal(b, &d); e != nil {
				return e
			}
		} else if !errors.Is(e, os.ErrNotExist) {
			return e
		}
		day := time.Now().UTC().Format("2006-01-02")
		if d.Day != day {
			d = dictationPaidBudget{Day: day}
		}
		if d.Requests < 0 || d.Characters < 0 || d.Seconds < 0 || d.Requests >= c.dailyRequests || n > c.dailyChars-d.Characters || c.seconds > c.dailySeconds-d.Seconds {
			return errDictationBudget
		}
		d.Requests++
		d.Characters += n
		d.Seconds += c.seconds
		return learningAtomicJSON(store.path, d)
	})
}
