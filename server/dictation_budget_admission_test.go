package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestDictationMonthlyRejectionDoesNotConsumeDailyAllowance(t *testing.T) {
	dictationPaidTestConfig(t)
	cfg, call := dictationTestAPI(t)
	root := filepath.Join(filepath.Dir(cfg.historyPath), "dictations")
	for i := 0; i < 10; i++ {
		if _, e := dictationReserveMonthly(root); e != nil {
			t.Fatal(e)
		}
	}
	if w := call("POST", "", `{"id":"limited","title":"Test","text":"Hallo.","language":"de"}`); w.Code != 200 {
		t.Fatal(w.Code)
	}
	calls := 0
	cfg.dictationSpeech = func(context.Context, dictationOpenAIConfig, string) ([]byte, error) { calls++; return nil, nil }
	for i := 0; i < 2; i++ {
		if w := call("POST", "/limited/audio/0", "{}"); w.Code != 429 {
			t.Fatal(w.Code, w.Body)
		}
	}
	if calls != 0 {
		t.Fatal("provider called")
	}
	if _, e := os.Stat(filepath.Join(root, "paid-budget.json")); !os.IsNotExist(e) {
		t.Fatal("monthly rejection consumed daily ledger", e)
	}
	_, session, err := cfg.auth.store.create("lifecycle-owner", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if e := cfg.dictationTransaction(session.UserID, false, func(d *dictationData) error {
		if len(d.Items) != 1 {
			t.Fatal("wrong fixture owner")
		}
		if d.Generations != 0 {
			t.Fatalf("rejection consumed owner generation: %d", d.Generations)
		}
		return nil
	}); e != nil {
		t.Fatal(e)
	}
}
