package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func TestDictationSettlementCrashAndCrossProcessReplay(t *testing.T) {
	if root := os.Getenv("KM_SYNTHETIC_SETTLEMENT_CHILD"); root != "" {
		b, err := os.ReadFile(filepath.Join(root, "ticket.json"))
		if err != nil {
			os.Exit(21)
		}
		var v struct{ Month, ID string }
		if json.Unmarshal(b, &v) != nil {
			os.Exit(22)
		}
		u := dictationSpeechUsage{InputTokens: 10, OutputTokens: 20}
		u.Input.TextTokens = 10
		u.Output.AudioTokens = 20
		if dictationRecordCompletedUsage(root, dictationBudgetTicket{month: v.Month, id: v.ID}, "durable-response", u) != nil {
			os.Exit(23)
		}
		// Hard process exit before any application acknowledgment/audio publication.
		os.Exit(0)
	}
	root := t.TempDir()
	ticket, err := dictationReserveMonthly(root)
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(struct{ Month, ID string }{ticket.month, ticket.id})
	if err = os.WriteFile(filepath.Join(root, "ticket.json"), b, 0600); err != nil {
		t.Fatal(err)
	}
	child := func() *exec.Cmd {
		c := exec.Command(os.Args[0], "-test.run=^TestDictationSettlementCrashAndCrossProcessReplay$")
		c.Env = append(os.Environ(), "KM_SYNTHETIC_SETTLEMENT_CHILD="+root)
		return c
	}
	if out, err := child().CombinedOutput(); err != nil {
		t.Fatalf("child failed: %v %s", err, out)
	}
	path := filepath.Join(root, "paid-months", ticket.month+".json")
	before, _ := os.ReadFile(path)
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if out, e := child().CombinedOutput(); e != nil {
				t.Errorf("retry child: %v %s", e, out)
			}
		}()
	}
	wg.Wait()
	after, _ := os.ReadFile(path)
	if string(before) != string(after) {
		t.Fatal("crash/replay modified receipt")
	}
	var d dictationMonthlyLedger
	if err = json.Unmarshal(after, &d); err != nil {
		t.Fatal(err)
	}
	got, err := dictationMonthlyAccounted(&d, ticket.month)
	if err != nil || got != 406 {
		t.Fatal(got, err)
	}
}

func TestDictationSettlementConcurrentAdmissionAndReplay(t *testing.T) {
	root := t.TempDir()
	var tickets []dictationBudgetTicket
	for i := 0; i < 10; i++ {
		v, e := dictationReserveMonthly(root)
		if e != nil {
			t.Fatal(e)
		}
		tickets = append(tickets, v)
	}
	u := dictationSpeechUsage{InputTokens: 10, OutputTokens: 20}
	u.Input.TextTokens = 10
	u.Output.AudioTokens = 20
	var wg sync.WaitGroup
	for i, v := range tickets {
		for j := 0; j < 3; j++ {
			wg.Add(1)
			go func(i int, v dictationBudgetTicket) {
				defer wg.Done()
				if err := dictationRecordCompletedUsage(root, v, fmt.Sprintf("r-%d", i), u); err != nil {
					t.Error(err)
				}
				_, _ = dictationReserveMonthly(root)
			}(i, v)
		}
	}
	wg.Wait()
	// Saturate remaining headroom after the final racing receipt has committed.
	for i := 0; i < 10; i++ {
		if _, err := dictationReserveMonthly(root); err != nil {
			break
		}
	}
	month := time.Now().UTC().Format("2006-01")
	b, err := os.ReadFile(filepath.Join(root, "paid-months", month+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var d dictationMonthlyLedger
	if err = json.Unmarshal(b, &d); err != nil {
		t.Fatal(err)
	}
	got, err := dictationMonthlyAccounted(&d, month)
	if err != nil || got > dictationMonthlyMicroUSD || got <= dictationMonthlyMicroUSD-dictationAttemptMicroUSD {
		t.Fatal(got, err)
	}
	receipts := 0
	for _, v := range d.Entries {
		if v.Settlement != nil {
			receipts++
		}
	}
	if receipts != 10 || len(d.Entries) != 19 {
		t.Fatalf("lost receipt or double release: %d receipts %d entries", receipts, len(d.Entries))
	}
}
