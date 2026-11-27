package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func reviewProducerLock(t *testing.T, root string) {
	t.Helper()
	f, err := os.OpenFile(filepath.Join(root, "generation.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		t.Fatal(err)
	}
	if err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { syscall.Flock(int(f.Fd()), syscall.LOCK_UN); f.Close() })
}

func reviewLedgerBytes(t *testing.T, d dictationMonthlyLedger) []byte {
	t.Helper()
	b, err := json.Marshal(d)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestDictationReviewPersistedSchemaAliases(t *testing.T) {
	u := `{"input_tokens":1,"output_tokens":1,"input_token_details":{"text_tokens":1,"audio_tokens":0,"image_tokens":0},"output_token_details":{"text_tokens":0,"audio_tokens":1}}`
	valid := `{"entries":[{"id":"legacy","reserved_micro_usd":1000000,"reported_cost_micro_usd":21,"reported_usage":` + u + `}]}`
	for name, raw := range map[string]string{
		"upper-usage-unknown":   strings.Replace(strings.Replace(valid, "reported_usage", "REPORTED_USAGE", 1), `"image_tokens":0`, `"image_tokens":0,"future_version":2`, 1),
		"upper-usage":           strings.Replace(valid, "reported_usage", "REPORTED_USAGE", 1),
		"nested-alias":          strings.Replace(valid, "input_token_details", "INPUT_TOKEN_DETAILS", 1),
		"root-alias":            strings.Replace(valid, "entries", "ENTRIES", 1),
		"duplicate-usage-alias": strings.Replace(valid, `"reported_usage":`, `"REPORTED_USAGE":`+u+`,"reported_usage":`, 1),
		"duplicate-usage":       strings.Replace(valid, `"reported_usage":`, `"reported_usage":`+u+`,"reported_usage":`, 1),
		"duplicate-nested":      strings.Replace(valid, `"image_tokens":0`, `"image_tokens":0,"image_tokens":0`, 1),
		"duplicate-policy":      strings.Replace(valid, `{"entries"`, `{"attempt_policy":2,"attempt_policy":1,"entries"`, 1),
	} {
		t.Run(name, func(t *testing.T) {
			root := t.TempDir()
			reviewProducerLock(t, root)
			month := time.Now().UTC().Format("2006-01")
			path := filepath.Join(root, "paid-months", month+".json")
			if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(path, []byte(raw), 0600); err != nil {
				t.Fatal(err)
			}
			// Exercise the default persisted decoder/writer, not a test-only decoder.
			if err := dictationMonthlyTransaction(root, month, func(*dictationMonthlyLedger) error { return nil }); err == nil {
				t.Error("ambiguous persisted schema accepted by production transaction")
			}
			after, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(after, []byte(raw)) {
				t.Error("original persisted evidence rewritten")
			}
		})
	}
}

func TestDictationReviewUnreadableEnumeration(t *testing.T) {
	root := t.TempDir()
	reviewProducerLock(t, root)
	c := dictationOpenAIConfig{chars: 1800, seconds: 10, dailyChars: 100, dailySeconds: 20, dailyRequests: 2}
	ticket, err := dictationPrepareAttempt(root, "owner", "asset")
	if err != nil {
		t.Fatal(err)
	}
	if err = dictationMarkAttempted(root, ticket, c, "Hallo.", "owner", 0); err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join(root, "paid-months")
	path := filepath.Join(dir, ticket.month+".json")
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.Chmod(dir, 0300); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chmod(dir, 0700) })
	if _, err = os.ReadDir(dir); !errors.Is(err, os.ErrPermission) {
		t.Fatalf("fixture requires genuine unreadable enumeration: %v", err)
	}
	_, err = dictationPrepareAttempt(root, "owner", "asset")
	if !errors.Is(err, os.ErrPermission) {
		t.Errorf("enumeration error not propagated: %v", err)
	}
	if err = os.Chmod(dir, 0700); err != nil {
		t.Fatal(err)
	}
	after, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Error("unreadable enumeration mutated ledger / created duplicate active key")
	}
	if err = dictationRecoverPrepared(root); err != nil {
		t.Errorf("subsequent recovery poisoned: %v", err)
	}
	if _, err = dictationPrepareAttempt(root, "owner", "asset"); !errors.Is(err, errDictationRecovery) {
		t.Errorf("original attempted identity lost: %v", err)
	}
}

// Pad a valid legacy ID so a new prepared entry fits exactly remaining bytes
// below the storage ceiling. This is a real accepted ledger, with no size hooks.
func reviewStorageFixture(t *testing.T, root string, remaining int) (string, []byte) {
	t.Helper()
	month := time.Now().UTC().Format("2006-01")
	d := dictationMonthlyLedger{AttemptPolicy: 1, Entries: []dictationMonthlyEntry{
		{ID: "legacy", MicroUSD: dictationAttemptMicroUSD},
		{ID: strings.Repeat("a", 32), OwnerHash: sessionHash("owner"), MicroUSD: dictationAttemptMicroUSD, Attempt: &dictationAttempt{Version: 1, Key: sessionHash("owner\x00asset"), State: "prepared"}},
	}}
	pad := dictationMonthlyMaxBytes - remaining - len(reviewLedgerBytes(t, d))
	d.Entries[0].ID += strings.Repeat("x", pad)
	if len(reviewLedgerBytes(t, d)) != dictationMonthlyMaxBytes-remaining {
		t.Fatal("fixture size")
	}
	d.Entries = d.Entries[:1]
	raw := reviewLedgerBytes(t, d)
	path := filepath.Join(root, "paid-months", month+".json")
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, raw, 0600); err != nil {
		t.Fatal(err)
	}
	return path, raw
}

func TestDictationReviewStorageHeadroom(t *testing.T) {
	for _, remaining := range []int{10, 100, 1700} {
		t.Run(strconv.Itoa(remaining)+"-bytes", func(t *testing.T) {
			root := t.TempDir()
			reviewProducerLock(t, root)
			path, before := reviewStorageFixture(t, root, remaining)
			ticket, err := dictationPrepareAttempt(root, "owner", "asset")
			if err == nil {
				t.Error("prepared admitted without room for all release/dispatch/completed evidence")
				if remaining == 10 {
					if err = dictationReleasePrepared(root, ticket); err != nil {
						t.Errorf("never-sent release stranded: %v", err)
					}
					if err = dictationRecoverPrepared(root); err != nil {
						t.Errorf("subsequent recovery stranded: %v", err)
					}
				} else {
					c := dictationOpenAIConfig{chars: 1800, seconds: 180, dailyChars: 10000, dailySeconds: 1000, dailyRequests: 10}
					if err = dictationMarkAttempted(root, ticket, c, strings.Repeat("x", 1800), "owner", 0); err != nil {
						t.Errorf("dispatch stranded: %v", err)
					} else {
						u := dictationSpeechUsage{InputTokens: 128000, OutputTokens: 32000}
						u.Input.TextTokens = 128000
						u.Output.AudioTokens = 32000
						if err = dictationRecordCompletedUsage(root, ticket, strings.Repeat("\x00", 256), u); err != nil {
							t.Errorf("completed settlement stranded: %v", err)
						}
					}
				}
			} else if !errors.Is(err, errDictationBudget) {
				t.Fatal(err)
			}
			after, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(before, after) {
				t.Error("storage refusal changed original ledger")
			}
		})
	}
}

func TestDictationReviewStorageAdmittedLifecycle(t *testing.T) {
	for _, action := range []string{"release", "recover", "complete"} {
		t.Run(action, func(t *testing.T) {
			root := t.TempDir()
			reviewProducerLock(t, root)
			path, _ := reviewStorageFixture(t, root, 3000)
			ticket, err := dictationPrepareAttempt(root, "owner", "asset")
			if err != nil {
				t.Fatal(err)
			}
			switch action {
			case "release":
				err = dictationReleasePrepared(root, ticket)
			case "recover":
				err = dictationRecoverPrepared(root)
			case "complete":
				c := dictationOpenAIConfig{chars: 1800, seconds: 180, dailyChars: 10000, dailySeconds: 1000, dailyRequests: 10}
				if err = dictationMarkAttempted(root, ticket, c, strings.Repeat("x", 1800), "owner", 0); err != nil {
					t.Fatal(err)
				}
				u := dictationSpeechUsage{InputTokens: 128000, OutputTokens: 32000}
				u.Input.TextTokens = 128000
				u.Output.AudioTokens = 32000
				err = dictationRecordCompletedUsage(root, ticket, strings.Repeat("\x00", 256), u)
			}
			if err != nil {
				t.Fatal(err)
			}
			raw, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			var d dictationMonthlyLedger
			if err = json.Unmarshal(raw, &d); err != nil {
				t.Fatal(err)
			}
			want := int64(dictationAttemptMicroUSD)
			if action == "complete" {
				want += 716800
			}
			if got, err := dictationMonthlyAccounted(&d, ticket.month); err != nil || got != want {
				t.Fatalf("charge %d want %d: %v", got, want, err)
			}
			if len(raw) > dictationMonthlyMaxBytes {
				t.Fatal("oversized ledger")
			}
		})
	}
}
