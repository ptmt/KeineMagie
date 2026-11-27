package main

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"sync/atomic"
	"syscall"
	"testing"
)

func TestDictationAttemptProcessCrash(t *testing.T) {
	if root := os.Getenv("KM_ATTEMPT_CRASH_ROOT"); root != "" {
		mode := os.Getenv("KM_ATTEMPT_CRASH_MODE")
		lock, err := os.OpenFile(filepath.Join(root, "generation.lock"), os.O_CREATE|os.O_RDWR, 0600)
		if err != nil {
			os.Exit(30)
		}
		if syscall.Flock(int(lock.Fd()), syscall.LOCK_EX) != nil {
			os.Exit(31)
		}
		ticket, err := dictationPrepareAttempt(root, "owner", "asset/0")
		if err != nil {
			os.Exit(32)
		}
		c := dictationOpenAIConfig{model: "gpt-realtime-2.1-mini", key: "synthetic", chars: 1800, seconds: 10, tokens: 100, timeout: 3, dailyRequests: 2, dailyChars: 100, dailySeconds: 20}
		var calls atomic.Int32
		endpoint := dictationAttemptWire(t, "complete", nil, &calls)
		c.beforeAttempt = func(attemptCtx context.Context) error {
			if mode == "before-intent" {
				os.Exit(0)
			}
			if err := dictationMarkAttempted(root, ticket, c, "Hallo.", "owner", 0); err != nil {
				os.Exit(33)
			}
			if mode == "after-intent" {
				os.Exit(0)
			}
			return nil
		}
		c.completedUsage = func(id string, u dictationSpeechUsage) error {
			if mode == "before-receipt" {
				os.Exit(0)
			}
			if err := dictationRecordCompletedUsage(root, ticket, id, u); err != nil {
				os.Exit(34)
			}
			os.Exit(0)
			return nil
		}
		if _, err = dictationRealtime(context.Background(), c, "Hallo.", endpoint); err != nil {
			os.Exit(35)
		}
		os.Exit(36)
	}
	for _, mode := range []string{"before-intent", "after-intent", "before-receipt", "after-receipt"} {
		t.Run(mode, func(t *testing.T) {
			root := t.TempDir()
			cmd := exec.Command(os.Args[0], "-test.run=^TestDictationAttemptProcessCrash$")
			cmd.Env = append(os.Environ(), "KM_ATTEMPT_CRASH_ROOT="+root, "KM_ATTEMPT_CRASH_MODE="+mode)
			if out, err := cmd.CombinedOutput(); err != nil {
				t.Fatalf("child: %v %s", err, out)
			}
			// Reacquiring the sole producer lock is the proof the killed producer is gone.
			lock, err := os.OpenFile(filepath.Join(root, "generation.lock"), os.O_RDWR, 0600)
			if err != nil {
				t.Fatal(err)
			}
			defer lock.Close()
			if err = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
				t.Fatal(err)
			}
			defer syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)
			var original dictationMonthlyEntry
			if err = dictationAttemptLedgers(root, func(_ string, d *dictationMonthlyLedger) error { original = d.Entries[0]; return nil }); err != nil {
				t.Fatal(err)
			}
			expected := "attempted"
			if mode == "before-intent" {
				expected = "prepared"
			}
			if mode == "after-receipt" {
				expected = "completed"
			}
			if original.Attempt.State != expected {
				t.Fatal(original.Attempt)
			}
			_, err = dictationPrepareAttempt(root, "owner", "asset/0")
			if mode == "before-intent" {
				if err != nil {
					t.Fatal(err)
				}
			} else if !errors.Is(err, errDictationRecovery) {
				t.Fatal("crashed attempt retried", err)
			}
			if err = dictationAttemptLedgers(root, func(month string, d *dictationMonthlyLedger) error {
				total, e := dictationMonthlyAccounted(d, month)
				want := dictationAttemptMicroUSD
				if mode == "after-receipt" {
					want = 406
				}
				// Before intent: old hold released; a fresh prepared hold replaces it.
				if e != nil || total != want {
					t.Errorf("charge=%d want=%d err=%v", total, want, e)
				}
				if mode == "before-intent" && d.Entries[0].Attempt.ReleaseProof != "prepared-no-response-create-v1" {
					t.Error("release lacks proof")
				}
				return nil
			}); err != nil {
				t.Fatal(err)
			}
		})
	}
}
