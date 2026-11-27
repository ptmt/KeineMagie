package main

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDictationNeverSentDoesNotConsumeAllowance(t *testing.T) {
	dictationPaidTestConfig(t)
	cfg, call := dictationTestAPI(t)
	if w := call("POST", "", `{"id":"never","title":"Test","text":"Hallo.","language":"de"}`); w.Code != 200 {
		t.Fatal(w.Code)
	}
	calls := 0
	cfg.dictationSpeech = func(context.Context, dictationOpenAIConfig, string) ([]byte, error) {
		calls++
		return nil, errors.New("synthetic dial failure before response.create")
	}
	for i := 0; i < 4; i++ {
		if w := call("POST", "/never/audio/0", "{}"); w.Code != 503 {
			t.Fatalf("never-sent request %d consumed allowance: %d %s", i, w.Code, w.Body)
		}
	}
	root := filepath.Join(filepath.Dir(cfg.historyPath), "dictations")
	month := time.Now().UTC().Format("2006-01")
	if err := dictationMonthlyTransaction(root, month, func(d *dictationMonthlyLedger) error {
		total, e := dictationMonthlyAccounted(d, month)
		if e != nil || total != 0 {
			t.Errorf("never-sent holds=%d error=%v", total, e)
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if calls != 4 {
		t.Fatal(calls)
	}
}

func TestDictationAttemptLifecycle(t *testing.T) {
	root := t.TempDir()
	owner := "owner"
	c := dictationOpenAIConfig{chars: 1800, seconds: 10, dailyChars: 100, dailySeconds: 20, dailyRequests: 2}
	first, err := dictationPrepareAttempt(root, owner, "asset/0")
	if err != nil {
		t.Fatal(err)
	}
	second, err := dictationPrepareAttempt(root, owner, "asset/0")
	if err != nil {
		t.Fatal("prepared crash recovery", err)
	}
	if first == second {
		t.Fatal("reused ID")
	}
	if err = dictationMarkAttempted(root, second, c, "Hallo.", owner, 0); err != nil {
		t.Fatal(err)
	}
	if _, err = dictationPrepareAttempt(root, owner, "asset/0"); !errors.Is(err, errDictationRecovery) {
		t.Fatal("attempted retried", err)
	}
	// An identical asset key belonging to another owner is independent.
	third, err := dictationPrepareAttempt(root, "other", "asset/0")
	if err != nil {
		t.Fatal(err)
	}
	if err = dictationMarkAttempted(root, third, c, "Hallo.", "other", 0); err != nil {
		t.Fatal(err)
	}
	fourth, err := dictationPrepareAttempt(root, owner, "asset/1")
	if err != nil {
		t.Fatal(err)
	}
	if err = dictationMarkAttempted(root, fourth, c, "Hallo.", owner, 0); !errors.Is(err, errDictationBudget) {
		t.Fatal("daily quota not durable", err)
	}
	if err = dictationReleasePrepared(root, fourth); err != nil {
		t.Fatal(err)
	}
	var total int64
	if err = dictationMonthlyTransaction(root, first.month, func(d *dictationMonthlyLedger) error {
		var e error
		total, e = dictationMonthlyAccounted(d, first.month)
		return e
	}); err != nil || total != 2*dictationAttemptMicroUSD {
		t.Fatal(total, err)
	}
}

func TestDictationAttemptUnknownSchemaFailsClosed(t *testing.T) {
	for _, mode := range []string{"null-root", "missing-entries", "null-entries", "root-field", "root-version", "policy", "entry-field", "attempt-field", "attempt-version", "state", "missing-proof", "usage-field", "duplicate-id"} {
		t.Run(mode, func(t *testing.T) {
			root := t.TempDir()
			ticket, err := dictationPrepareAttempt(root, "owner", "asset")
			if err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(root, "paid-months", ticket.month+".json")
			b, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			var d map[string]any
			json.Unmarshal(b, &d)
			v := d["entries"].([]any)[0].(map[string]any)
			a := v["attempt"].(map[string]any)
			switch mode {
			case "null-root":
				d = nil
			case "missing-entries":
				delete(d, "entries")
			case "null-entries":
				d["entries"] = nil
			case "root-field":
				d["future"] = true
			case "root-version":
				d["version"] = 2
			case "policy":
				d["attempt_policy"] = 2
			case "entry-field":
				v["future"] = true
			case "attempt-field":
				a["future"] = true
			case "attempt-version":
				a["version"] = 2
			case "state":
				a["state"] = "abandoned"
			case "missing-proof":
				a["state"] = "released"
			case "usage-field":
				v["reported_usage"] = map[string]any{"future": 1}
			case "duplicate-id":
				d["entries"] = []any{v, v}
			}
			b, _ = json.Marshal(d)
			if err = os.WriteFile(path, b, 0600); err != nil {
				t.Fatal(err)
			}
			if _, err = dictationPrepareAttempt(root, "owner", "other"); err == nil {
				t.Fatal("unknown schema admitted")
			}
			after, _ := os.ReadFile(path)
			if string(after) != string(b) {
				t.Fatal("unrecognized original rewritten")
			}
		})
	}
}

func TestDictationAttemptRolloverAndLegacyLimits(t *testing.T) {
	root := t.TempDir()
	owner := "owner"
	c := dictationOpenAIConfig{chars: 1800, seconds: 10, dailyRequests: 10, dailyChars: 1000, dailySeconds: 100}
	ticket, err := dictationPrepareAttempt(root, owner, "asset")
	if err != nil {
		t.Fatal(err)
	}
	if err = dictationMarkAttempted(root, ticket, c, "Hallo.", owner, 0); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(root, "paid-months", ticket.month+".json")
	old := time.Now().UTC().AddDate(0, -1, 0).Format("2006-01")
	if err = os.Rename(path, filepath.Join(root, "paid-months", old+".json")); err != nil {
		t.Fatal(err)
	}
	if _, err = dictationPrepareAttempt(root, owner, "asset"); !errors.Is(err, errDictationRecovery) {
		t.Fatal("month reset idempotency", err)
	}
	other, err := dictationPrepareAttempt(root, owner, "other")
	if err != nil {
		t.Fatal(err)
	}
	if err = dictationMarkAttempted(root, dictationBudgetTicket{old, ticket.id}, c, "Hallo.", owner, 0); err == nil {
		t.Fatal("sent old-month prepared/attempted")
	}
	// Legacy owner allowance is combined with the new attempted admission above.
	if err = dictationMarkAttempted(root, other, c, "Hallo.", owner, 119); !errors.Is(err, errDictationBudget) {
		t.Fatal("owner limit ignored", err)
	}
	day := time.Now().UTC().Format("2006-01-02")
	legacy := dictationPaidBudget{Day: day, Requests: 9, Characters: 1, Seconds: 1}
	raw, _ := json.Marshal(legacy)
	if err = os.WriteFile(filepath.Join(root, "paid-budget.json"), raw, 0600); err != nil {
		t.Fatal(err)
	}
	if err = dictationMarkAttempted(root, other, c, "Hallo.", owner, 0); !errors.Is(err, errDictationBudget) {
		t.Fatal("legacy shared limit ignored", err)
	}
	after, _ := os.ReadFile(filepath.Join(root, "paid-budget.json"))
	if string(raw) != string(after) {
		t.Fatal("legacy daily changed")
	}
}

func TestDictationLockedAdmissionRecoversPreparedWithMissingConfig(t *testing.T) {
	cfg, call := dictationTestAPI(t)
	if w := call("POST", "", `{"id":"recovery","title":"Test","text":"Hallo.","language":"de"}`); w.Code != 200 {
		t.Fatal(w.Code)
	}
	root := filepath.Join(filepath.Dir(cfg.historyPath), "dictations")
	ticket, err := dictationPrepareAttempt(root, "owner", "prior")
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("DICTATION_TTS_PROVIDER", "")
	if w := call("POST", "/recovery/audio/0", "{}"); w.Code != 503 {
		t.Fatal(w.Code)
	}
	if err = dictationAttemptLedgers(root, func(_ string, d *dictationMonthlyLedger) error {
		if d.Entries[0].ID != ticket.id || d.Entries[0].Attempt.State != "released" {
			t.Error("next locked admission left safe hold")
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
}

func TestDictationAttemptWritePreservesOperatorOverrides(t *testing.T) {
	root := t.TempDir()
	month := "2026-11"
	d := dictationMonthlyLedger{}
	for i := 0; i < 10; i++ {
		u := dictationSpeechUsage{InputTokens: 1, OutputTokens: 1}
		u.Input.TextTokens = 1
		u.Output.AudioTokens = 1
		v := dictationMonthlyEntry{ID: fmt.Sprintf("20261120T1200%02d.000000000", i), MicroUSD: dictationAttemptMicroUSD, Usage: &u, ActualMicroUSD: 21}
		original, _ := json.Marshal(v)
		v.OperatorRecovery = &dictationOperatorRecovery{Policy: "november-2026-unknown-cost-reserve-v1", ReserveMicroUSD: 800000, OriginalSHA256: fmt.Sprintf("%x", sha256.Sum256(original)), AuditID: "20261127-operator-authorized-stale-holds"}
		d.Entries = append(d.Entries, v)
	}
	originals, _ := json.Marshal(d.Entries)
	path := filepath.Join(root, "paid-months", month+".json")
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	raw, _ := json.Marshal(d)
	if err := os.WriteFile(path, raw, 0600); err != nil {
		t.Fatal(err)
	}
	if err := dictationMonthlyTransaction(root, month, func(d *dictationMonthlyLedger) error {
		d.AttemptPolicy = 1
		d.Entries = append(d.Entries, dictationMonthlyEntry{ID: strings.Repeat("a", 32), OwnerHash: sessionHash("owner"), MicroUSD: dictationAttemptMicroUSD, Attempt: &dictationAttempt{Version: 1, Key: sessionHash("owner\x00asset"), State: "prepared"}})
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if err := dictationReleasePrepared(root, dictationBudgetTicket{month, strings.Repeat("a", 32)}); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(path)
	if err := json.Unmarshal(b, &d); err != nil {
		t.Fatal(err)
	}
	after, _ := json.Marshal(d.Entries[:10])
	if string(originals) != string(after) {
		t.Fatal("original ownerunknown/recovery fields changed")
	}
	total, err := dictationMonthlyAccounted(&d, month)
	if err != nil || total != 8000000 {
		t.Fatal(total, err)
	}
	for _, v := range d.Entries[:10] {
		if v.OwnerHash != "" || v.Settlement != nil || v.Attempt != nil {
			t.Fatal("legacy evidence invented")
		}
	}
}

func TestDictationRecoveryDoesNotMutateBeforeAllSchemasValidated(t *testing.T) {
	root := t.TempDir()
	ticket, err := dictationPrepareAttempt(root, "owner", "asset")
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(root, "paid-months", ticket.month+".json")
	before, _ := os.ReadFile(path)
	if err = os.WriteFile(filepath.Join(root, "paid-months", "9999-12.json"), []byte(`{"attempt_policy":2,"entries":[]}`), 0600); err != nil {
		t.Fatal(err)
	}
	if err = dictationRecoverPrepared(root); err == nil {
		t.Fatal("future schema admitted")
	}
	after, _ := os.ReadFile(path)
	if string(before) != string(after) {
		t.Fatal("recovery mutated before all schemas validated")
	}
}

func TestDictationAttemptUnknownLegacyDailyFailsClosed(t *testing.T) {
	for _, mode := range []string{"future-field", "version", "missing-field", "invalid-day", "null"} {
		t.Run(mode, func(t *testing.T) {
			root := t.TempDir()
			ticket, err := dictationPrepareAttempt(root, "owner", "asset")
			if err != nil {
				t.Fatal(err)
			}
			raw := map[string]any{"day": time.Now().UTC().Format("2006-01-02"), "requests": 1, "characters": 1, "reserved_seconds": 1}
			switch mode {
			case "future-field":
				raw["future_quota"] = 1
			case "version":
				raw["version"] = 2
			case "missing-field":
				delete(raw, "requests")
			case "invalid-day":
				raw["day"] = "bad"
			case "null":
				raw["requests"] = nil
			}
			b, _ := json.Marshal(raw)
			path := filepath.Join(root, "paid-budget.json")
			if err = os.WriteFile(path, b, 0600); err != nil {
				t.Fatal(err)
			}
			c := dictationOpenAIConfig{chars: 1800, seconds: 10, dailyRequests: 10, dailyChars: 1000, dailySeconds: 100}
			if err = dictationMarkAttempted(root, ticket, c, "Hallo.", "owner", 0); err == nil {
				t.Error("unrecognized legacy daily schema admitted")
			}
			after, _ := os.ReadFile(path)
			if string(b) != string(after) {
				t.Fatal("legacy counters rewritten")
			}
		})
	}
}
