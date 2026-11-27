package main

import (
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"testing"
	"time"
)

func TestDictationInjectedAtomicKillWindows(t *testing.T) {
	if root := os.Getenv("KM_ATOMIC_CHILD_ROOT"); root != "" {
		producer, err := os.OpenFile(filepath.Join(root, "generation.lock"), os.O_CREATE|os.O_RDWR, 0600)
		if err != nil {
			t.Fatal(err)
		}
		defer producer.Close()
		if err = syscall.Flock(int(producer.Fd()), syscall.LOCK_EX); err != nil {
			t.Fatal(err)
		}
		defer syscall.Flock(int(producer.Fd()), syscall.LOCK_UN)
		transition := os.Getenv("KM_ATOMIC_TRANSITION")
		month := time.Now().UTC().Format("2006-01")
		var ticket dictationBudgetTicket
		c := dictationOpenAIConfig{chars: 1800, seconds: 10, dailyChars: 100, dailySeconds: 20, dailyRequests: 2}
		if transition != "prepare" {
			var err error
			ticket, err = dictationPrepareAttempt(root, "owner", "asset/0")
			if err != nil {
				t.Fatal(err)
			}
			if transition == "complete" {
				if err = dictationMarkAttempted(root, ticket, c, "Hallo.", "owner", 0); err != nil {
					t.Fatal(err)
				}
			}
		}
		// Install only an explicit isolated synthetic target after setup commits.
		os.Setenv("KM_ATOMIC_KILL_PATH", filepath.Join(root, "paid-months", month+".json"))
		os.Setenv("KM_ATOMIC_KILL_POINT", os.Getenv("KM_ATOMIC_POINT"))
		switch transition {
		case "prepare":
			_, _ = dictationPrepareAttempt(root, "owner", "asset/0")
		case "dispatch":
			_ = dictationMarkAttempted(root, ticket, c, "Hallo.", "owner", 0)
		case "release":
			_ = dictationReleasePrepared(root, ticket)
		case "complete":
			u := dictationSpeechUsage{InputTokens: 10, OutputTokens: 20}
			u.Input.TextTokens = 10
			u.Output.AudioTokens = 20
			_ = dictationRecordCompletedUsage(root, ticket, "synthetic-response", u)
		}
		t.Fatal("fault hook did not kill process")
	}
	for _, transition := range []string{"prepare", "dispatch", "complete", "release"} {
		for _, point := range []string{"before-write", "after-write", "before-file-sync", "after-file-sync", "before-close", "after-close", "before-rename", "after-rename", "before-dir-sync", "after-dir-sync"} {
			t.Run(transition+"/"+point, func(t *testing.T) {
				root := t.TempDir()
				cmd := exec.Command(os.Args[0], "-test.run=^TestDictationInjectedAtomicKillWindows$")
				cmd.Env = append(os.Environ(), "KM_ATOMIC_CHILD_ROOT="+root, "KM_ATOMIC_TRANSITION="+transition, "KM_ATOMIC_POINT="+point)
				out, err := cmd.CombinedOutput()
				var exit *exec.ExitError
				if !errors.As(err, &exit) || !exit.ProcessState.Sys().(syscall.WaitStatus).Signaled() || exit.ProcessState.Sys().(syscall.WaitStatus).Signal() != syscall.SIGKILL {
					t.Fatalf("not SIGKILL: %v %s", err, out)
				}
				lock, err := os.OpenFile(filepath.Join(root, "generation.lock"), os.O_CREATE|os.O_RDWR, 0600)
				if err != nil {
					t.Fatal(err)
				}
				defer lock.Close()
				if err = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
					t.Fatal(err)
				}
				defer syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)
				month := time.Now().UTC().Format("2006-01")
				b, err := os.ReadFile(filepath.Join(root, "paid-months", month+".json"))
				committed := point == "after-rename" || point == "before-dir-sync" || point == "after-dir-sync"
				if transition == "prepare" && !committed {
					if !os.IsNotExist(err) {
						t.Fatalf("uncommitted prepare visible %v", err)
					}
					return
				}
				if err != nil {
					t.Fatal(err)
				}
				var ledger dictationMonthlyLedger
				if err = json.Unmarshal(b, &ledger); err != nil {
					t.Fatal("partial ledger", err)
				}
				if len(ledger.Entries) != 1 {
					t.Fatal("unexpected entries", len(ledger.Entries))
				}
				v := ledger.Entries[0]
				want := "prepared"
				if transition == "complete" {
					want = "attempted"
				}
				if committed {
					switch transition {
					case "dispatch":
						want = "attempted"
					case "complete":
						want = "completed"
					case "release":
						want = "released"
					}
				}
				if v.Attempt == nil || v.Attempt.State != want {
					t.Fatalf("state=%+v want=%s", v.Attempt, want)
				}
				dispatched := want == "attempted" || want == "completed"
				if (v.Attempt.Day != "") != dispatched || (v.Attempt.Characters > 0) != dispatched || (v.Attempt.Seconds > 0) != dispatched {
					t.Fatal("daily charge not atomic with intent")
				}
				cost, err := dictationMonthlyAccounted(&ledger, month)
				if err != nil {
					t.Fatal(err)
				}
				wantCost := dictationAttemptMicroUSD
				if want == "completed" {
					wantCost = 406
				}
				if want == "released" {
					wantCost = 0
				}
				if cost != wantCost {
					t.Fatal(cost, wantCost)
				}
				if err = dictationRecoverPrepared(root); err != nil {
					t.Fatal(err)
				}
				if dispatched {
					if _, err = dictationPrepareAttempt(root, "owner", "asset/0"); !errors.Is(err, errDictationRecovery) {
						t.Fatal("paid retry after crash", err)
					}
				}
			})
		}
	}
}
