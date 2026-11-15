package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestDictationMonthlyCrossProcessCrash(t *testing.T) {
	if root := os.Getenv("KM_SYNTHETIC_BUDGET_CHILD"); root != "" {
		ticket, err := dictationReserveMonthly(root)
		if err != nil {
			os.Exit(19)
		}
		if os.Getenv("KM_SYNTHETIC_BUDGET_CRASH") == "1" {
			os.WriteFile(filepath.Join(root, "reserved"), []byte(ticket.id), 0600)
			time.Sleep(30 * time.Second)
		}
		os.Exit(0)
	}
	root := t.TempDir()
	child := func(crash bool) *exec.Cmd {
		c := exec.Command(os.Args[0], "-test.run=^TestDictationMonthlyCrossProcessCrash$")
		c.Env = append(os.Environ(), "KM_SYNTHETIC_BUDGET_CHILD="+root)
		if crash {
			c.Env = append(c.Env, "KM_SYNTHETIC_BUDGET_CRASH=1")
		}
		return c
	}
	c := child(true)
	if err := c.Start(); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		if _, err := os.Stat(filepath.Join(root, "reserved")); err == nil {
			break
		}
		if time.Now().After(deadline) {
			c.Process.Kill()
			c.Wait()
			t.Fatal("child did not reserve")
		}
		time.Sleep(10 * time.Millisecond)
	}
	c.Process.Kill()
	c.Wait()
	var wg sync.WaitGroup
	var admitted atomic.Int32
	for i := 0; i < 16; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if child(false).Run() == nil {
				admitted.Add(1)
			}
		}()
	}
	wg.Wait()
	if admitted.Load() != 9 {
		t.Fatal("crash hold or cross-process limit lost", admitted.Load())
	}
	if _, err := dictationReserveMonthly(root); err == nil {
		t.Fatal("post-crash overspend")
	}
}

func TestDictationMonthlyTenDollarAdmission(t *testing.T) {
	root := t.TempDir()
	var admitted atomic.Int32
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, e := dictationReserveMonthly(root); e == nil {
				admitted.Add(1)
			}
		}()
	}
	wg.Wait()
	if admitted.Load() != 10 {
		t.Fatal("monthly admission", admitted.Load())
	}
	if _, e := dictationReserveMonthly(root); e == nil {
		t.Fatal("restart/uncertainty bypass")
	}
}

func TestDictationUsageAccountingNeverRefundsUncertainty(t *testing.T) {
	root := t.TempDir()
	ticket, e := dictationReserveMonthly(root)
	if e != nil {
		t.Fatal(e)
	}
	usage := dictationSpeechUsage{InputTokens: 100, OutputTokens: 200}
	usage.Input.TextTokens = 100
	usage.Output.AudioTokens = 190
	usage.Output.TextTokens = 10
	if e = dictationRecordUsage(root, ticket, usage); e != nil {
		t.Fatal(e)
	}
	if e = dictationRecordUsage(root, ticket, usage); e != nil {
		t.Fatal("duplicate usage reconciliation", e)
	}
	for i := 0; i < 9; i++ {
		if _, e = dictationReserveMonthly(root); e != nil {
			t.Fatal(e)
		}
	}
	if _, e = dictationReserveMonthly(root); e == nil {
		t.Fatal("actual accounting refunded conservative hold")
	}
	if cost, ok := dictationUsageMicroUSD(usage); !ok || cost != 3884 {
		t.Fatal(cost, ok)
	}
}
