package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"time"
)

var errDictationRecovery = errors.New("audio attempt requires recovery; automatic paid retry blocked")

type dictationRecoveryError struct{ Reason string }

func (e *dictationRecoveryError) Error() string { return errDictationRecovery.Error() }
func (e *dictationRecoveryError) Unwrap() error { return errDictationRecovery }
func dictationRecoveryForState(state string) error {
	reason := "attempt_outcome_uncertain"
	if state == "completed" {
		reason = "completed_audio_unavailable"
	}
	return &dictationRecoveryError{Reason: reason}
}

// Read only: used to explain this exact owner/asset failure, never global spend.
func dictationAttemptFailure(root string, t dictationBudgetTicket, fallback error) error {
	if errors.Is(fallback, errCoachUnauthorized) {
		return fallback
	}
	b, err := os.ReadFile(filepath.Join(root, "paid-months", t.month+".json"))
	if err != nil || len(b) > dictationMonthlyMaxBytes {
		return errDictationRecovery
	}
	var d dictationMonthlyLedger
	if json.Unmarshal(b, &d) != nil {
		return errDictationRecovery
	}
	if _, err = dictationMonthlyAccounted(&d, t.month); err != nil {
		return errDictationRecovery
	}
	for _, v := range d.Entries {
		if v.ID == t.id && v.Attempt != nil && (v.Attempt.State == "attempted" || v.Attempt.State == "completed") {
			return dictationRecoveryForState(v.Attempt.State)
		}
	}
	return fallback
}

// Policy 1 writers must preserve these fields. A prepared entry proves the only
// producer has not crossed beforeAttempt. Recovery requires generation.lock.
// Attempted is deliberately conservative across the durable-commit/send gap.
type dictationAttempt struct {
	Version      int    `json:"version"`
	Key          string `json:"key"`
	State        string `json:"state"`
	Day          string `json:"day,omitempty"`
	Characters   int    `json:"characters,omitempty"`
	Seconds      int    `json:"seconds,omitempty"`
	ReleaseProof string `json:"release_proof,omitempty"`
}

func dictationAttemptValid(v dictationMonthlyEntry) bool {
	a := v.Attempt
	if a == nil {
		return true
	}
	if a.Version != 1 || len(a.Key) != 64 || len(v.OwnerHash) != 64 || v.OperatorRecovery != nil {
		return false
	}
	if _, err := hex.DecodeString(a.Key); err != nil {
		return false
	}
	switch a.State {
	case "prepared", "released":
		return a.Day == "" && a.Characters == 0 && a.Seconds == 0 && v.Usage == nil && v.Settlement == nil && v.ActualMicroUSD == 0 && ((a.State == "prepared" && a.ReleaseProof == "") || (a.State == "released" && a.ReleaseProof == "prepared-no-response-create-v1"))
	case "attempted", "completed":
		day, err := time.Parse("2006-01-02", a.Day)
		return err == nil && day.Format("2006-01-02") == a.Day && a.Characters > 0 && a.Characters <= 1800 && a.Seconds > 0 && a.Seconds <= 180 && a.ReleaseProof == "" && ((a.State == "completed") == (v.Settlement != nil))
	}
	return false
}

// Called only while holding the sole producer generation.lock. Includes older
// months: owner/asset identity does not reset at midnight or month rollover.
func dictationAttemptLedgers(root string, visit func(string, *dictationMonthlyLedger) error) error {
	dir := filepath.Join(root, "paid-months")
	files, err := os.ReadDir(dir)
	if errors.Is(err, os.ErrNotExist) {
		return nil // No ledger directory exists on first admission.
	}
	if err != nil {
		return err
	}
	type ledger struct {
		month string
		data  dictationMonthlyLedger
	}
	var ledgers []ledger
	ids, responses, keys := map[string]bool{}, map[string]bool{}, map[string]bool{}
	for _, file := range files {
		if !strings.HasSuffix(file.Name(), ".json") {
			continue
		}
		p := filepath.Join(dir, file.Name())
		month := strings.TrimSuffix(file.Name(), ".json")
		parsed, parseErr := time.Parse("2006-01", month)
		if parseErr != nil || parsed.Format("2006-01") != month {
			return errDictationBudget
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		if len(b) > dictationMonthlyMaxBytes {
			return errDictationBudget
		}
		var d dictationMonthlyLedger
		if err = json.Unmarshal(b, &d); err != nil {
			return err
		}
		if _, err = dictationMonthlyAccounted(&d, month); err != nil {
			return err
		}
		for _, v := range d.Entries {
			if ids[v.ID] {
				return errDictationBudget
			}
			ids[v.ID] = true
			if v.Settlement != nil {
				if responses[v.Settlement.ResponseID] {
					return errDictationBudget
				}
				responses[v.Settlement.ResponseID] = true
			}
			if a := v.Attempt; a != nil && a.State != "released" {
				if keys[a.Key] {
					return errDictationBudget
				}
				keys[a.Key] = true
			}
		}
		ledgers = append(ledgers, ledger{month, d})
	}
	// Validate every month before invoking a visitor that may recover any holds.
	for _, v := range ledgers {
		if err = visit(v.month, &v.data); err != nil {
			return err
		}
	}
	return nil
}

func dictationReleasePrepared(root string, t dictationBudgetTicket) error {
	return dictationMonthlyTransaction(root, t.month, func(d *dictationMonthlyLedger) error {
		if _, err := dictationMonthlyAccounted(d, t.month); err != nil {
			return err
		}
		for i := range d.Entries {
			v := &d.Entries[i]
			if v.ID == t.id && v.Attempt != nil {
				if v.Attempt.State == "prepared" {
					v.Attempt.State = "released"
					v.Attempt.ReleaseProof = "prepared-no-response-create-v1"
				}
				return nil
			}
		}
		return errDictationBudget
	})
}

func dictationRecoverPrepared(root string) error {
	// Lock ownership proves all prior prepared producers are gone. No age heuristic.
	err := dictationAttemptLedgers(root, func(month string, d *dictationMonthlyLedger) error {
		for _, v := range d.Entries {
			if v.Attempt != nil && v.Attempt.State == "prepared" {
				if err := dictationReleasePrepared(root, dictationBudgetTicket{month, v.ID}); err != nil {
					return err
				}
			}
		}
		return nil
	})
	if err != nil {
		return err
	}

	return nil
}

func dictationPrepareAttempt(root, owner, asset string) (dictationBudgetTicket, error) {
	key := sessionHash(owner + "\x00" + asset)
	if err := dictationRecoverPrepared(root); err != nil {
		return dictationBudgetTicket{}, err
	}
	err := dictationAttemptLedgers(root, func(_ string, d *dictationMonthlyLedger) error {
		for _, v := range d.Entries {
			if v.Attempt != nil && v.Attempt.Key == key && v.Attempt.State != "released" {
				return dictationRecoveryForState(v.Attempt.State)
			}
		}
		return nil
	})
	if err != nil {
		return dictationBudgetTicket{}, err
	}
	t := dictationBudgetTicket{month: time.Now().UTC().Format("2006-01")}
	var nonce [16]byte
	if _, err = rand.Read(nonce[:]); err != nil {
		return t, err
	}
	t.id = hex.EncodeToString(nonce[:])
	err = dictationMonthlyTransaction(root, t.month, func(d *dictationMonthlyLedger) error {
		total, err := dictationMonthlyAccounted(d, t.month)
		if err != nil {
			return err
		}
		if total > dictationMonthlyMicroUSD-dictationAttemptMicroUSD {
			return errDictationBudget
		}
		d.AttemptPolicy = 1
		d.Entries = append(d.Entries, dictationMonthlyEntry{ID: t.id, OwnerHash: sessionHash(owner), MicroUSD: dictationAttemptMicroUSD, Attempt: &dictationAttempt{Version: 1, Key: key, State: "prepared"}})
		return dictationAttemptStorageHeadroom(d, t.month)
	})
	return t, err
}

// New daily admissions live in the SAME atomic transaction as attempted. Legacy
// daily and owner counters stay untouched and are included in today's limits.
func dictationMarkAttempted(root string, t dictationBudgetTicket, c dictationOpenAIConfig, text, owner string, legacyOwner int) error {
	now := time.Now().UTC()
	day := now.Format("2006-01-02")
	if t.month != now.Format("2006-01") {
		return errDictationBudget
	}
	n := runeCount(text)
	if n < 1 || n > c.chars || legacyOwner < 0 {
		return errDictationBudget
	}
	totals := dictationPaidBudget{Day: day}
	own := legacyOwner
	b, err := os.ReadFile(filepath.Join(root, "paid-budget.json"))
	if err == nil {
		if len(b) > 4096 {
			return errDictationBudget
		}
		var old dictationPaidBudget
		if dictationStrictJSON(b, &old) != nil {
			return errDictationBudget
		}
		var fields map[string]json.RawMessage
		if json.Unmarshal(b, &fields) != nil {
			return errDictationBudget
		}
		for _, k := range []string{"day", "requests", "characters", "reserved_seconds"} {
			v, ok := fields[k]
			if !ok || string(v) == "null" {
				return errDictationBudget
			}
		}
		parsed, err := time.Parse("2006-01-02", old.Day)
		if err != nil || parsed.Format("2006-01-02") != old.Day {
			return errDictationBudget
		}

		if old.Requests < 0 || old.Requests > 10000 || old.Characters < 0 || old.Characters > 1000000 || old.Seconds < 0 || old.Seconds > 86400 {
			return errDictationBudget
		}
		if old.Day == day {
			totals = old
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	err = dictationAttemptLedgers(root, func(_ string, d *dictationMonthlyLedger) error {
		for _, v := range d.Entries {
			a := v.Attempt
			if a != nil && a.Day == day {
				totals.Requests++
				totals.Characters += a.Characters
				totals.Seconds += a.Seconds
				if v.OwnerHash == sessionHash(owner) {
					own++
				}
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	if totals.Requests < 0 || totals.Characters < 0 || totals.Seconds < 0 || totals.Requests >= c.dailyRequests || n > c.dailyChars-totals.Characters || c.seconds > c.dailySeconds-totals.Seconds || own >= 120 {
		return errDictationBudget
	}
	return dictationMonthlyTransaction(root, t.month, func(d *dictationMonthlyLedger) error {
		if _, err := dictationMonthlyAccounted(d, t.month); err != nil {
			return err
		}
		for i := range d.Entries {
			v := &d.Entries[i]
			if v.ID == t.id && v.OwnerHash == sessionHash(owner) && v.Attempt != nil && v.Attempt.State == "prepared" {
				v.Attempt.State = "attempted"
				v.Attempt.Day = day
				v.Attempt.Characters = n
				v.Attempt.Seconds = c.seconds
				return dictationAttemptStorageHeadroom(d, t.month)
			}
		}
		return errDictationBudget
	})
}

// Admission reserves bytes as well as dollars. Keep room for every pending
// attempt's largest remaining transition, including JSON escaping of the full
// 256-byte response ID. Existing evidence is counted verbatim by the same encoder
// as the writer; legacy entries are never changed by these projections.
func dictationAttemptStorageHeadroom(d *dictationMonthlyLedger, month string) error {
	encoded, err := json.Marshal(d)
	if err != nil {
		return err
	}
	size := len(encoded)
	for _, v := range d.Entries {
		if v.Attempt == nil || (v.Attempt.State != "prepared" && v.Attempt.State != "attempted") {
			continue
		}
		current, err := json.Marshal(v)
		if err != nil {
			return err
		}
		a := *v.Attempt
		v.Attempt = &a
		a.State, a.Day, a.Characters, a.Seconds = "completed", "2000-01-01", 1800, 180
		// Deliberately overestimate all independently bounded token fields and cost.
		u := dictationSpeechUsage{InputTokens: 128000, OutputTokens: 32000}
		u.Input.TextTokens, u.Input.AudioTokens = 128000, 128000
		u.Output.TextTokens, u.Output.AudioTokens = 32000, 32000
		v.Usage, v.ActualMicroUSD = &u, dictationAttemptMicroUSD
		v.Settlement = &dictationSettlement{Version: 1, Currency: "USD", Model: "gpt-realtime-2.1-mini", RateCard: dictationRateCard, Status: "completed", ResponseID: strings.Repeat("\x00", 256), Month: month, ReservationID: v.ID}
		completed, err := json.Marshal(v)
		if err != nil {
			return err
		}
		maxBytes := len(completed)
		// Also bound the never-sent release, without mutating the actual attempt.
		a.State, a.Day, a.Characters, a.Seconds = "released", "", 0, 0
		a.ReleaseProof = "prepared-no-response-create-v1"
		v.Usage, v.Settlement, v.ActualMicroUSD = nil, nil, 0
		released, err := json.Marshal(v)
		if err != nil {
			return err
		}
		if len(released) > maxBytes {
			maxBytes = len(released)
		}
		if maxBytes > len(current) {
			size += maxBytes - len(current)
		}
		if size > dictationMonthlyMaxBytes {
			return errDictationBudget
		}
	}
	if size > dictationMonthlyMaxBytes {
		return errDictationBudget
	}
	return nil
}
