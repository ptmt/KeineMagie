package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func recoveryFixture(t *testing.T) dictationMonthlyEntry {
	t.Helper()
	var v dictationMonthlyEntry
	if err := json.Unmarshal([]byte(`{"id":"20261120T120000.000000000","reserved_micro_usd":1000000,"reported_usage":{"input_tokens":1,"output_tokens":1,"input_token_details":{"text_tokens":1,"audio_tokens":0,"image_tokens":0},"output_token_details":{"text_tokens":0,"audio_tokens":1}},"reported_cost_micro_usd":21}`), &v); err != nil {
		t.Fatal(err)
	}
	recoveryMark(&v)
	return v
}
func recoveryMark(v *dictationMonthlyEntry) {
	b, _ := json.Marshal(v)
	v.OperatorRecovery = &dictationOperatorRecovery{Policy: "november-2026-unknown-cost-reserve-v1", ReserveMicroUSD: 800000, OriginalSHA256: fmt.Sprintf("%x", sha256.Sum256(b)), AuditID: "20261127-operator-authorized-stale-holds"}
}
func TestDictationOperatorRecoveryFailClosed(t *testing.T) {
	for name, change := range map[string]func(*dictationMonthlyEntry){
		"zero":   func(v *dictationMonthlyEntry) { v.OperatorRecovery.ReserveMicroUSD = 0 },
		"lower":  func(v *dictationMonthlyEntry) { v.OperatorRecovery.ReserveMicroUSD = 799999 },
		"digest": func(v *dictationMonthlyEntry) { v.OperatorRecovery.OriginalSHA256 = "" },
		"policy": func(v *dictationMonthlyEntry) { v.OperatorRecovery.Policy = "other" },
		"audit":  func(v *dictationMonthlyEntry) { v.OperatorRecovery.AuditID = "" },
		"owner":  func(v *dictationMonthlyEntry) { v.OwnerHash = "unknown-not-inferred" },
		"proof":  func(v *dictationMonthlyEntry) { v.Settlement = &dictationSettlement{} },
		"recent": func(v *dictationMonthlyEntry) { v.ID = "20261127T120000.000000000" },
		"usage":  func(v *dictationMonthlyEntry) { v.Usage = nil },
		"cost":   func(v *dictationMonthlyEntry) { v.ActualMicroUSD++ },
		"hold":   func(v *dictationMonthlyEntry) { v.MicroUSD-- },
	} {
		t.Run(name, func(t *testing.T) {
			v := recoveryFixture(t)
			change(&v)
			if _, err := dictationMonthlyAccounted(&dictationMonthlyLedger{Entries: []dictationMonthlyEntry{v}}, "2026-11"); err == nil {
				t.Fatal("accepted invalid recovery")
			}
		})
	}
	v := recoveryFixture(t)
	if _, err := dictationMonthlyAccounted(&dictationMonthlyLedger{Entries: []dictationMonthlyEntry{v}}, "2026-12"); err == nil {
		t.Fatal("cross-month recovery")
	}
}

// Operator-only opt-in: reads an exact private snapshot; writes ONLY a separate
// candidate path. Never accesses production, provider keys or network. The live
// apply is separately lock/hash-bound and audited by the deployment tool.
func TestDictationOperatorPrepareSnapshot(t *testing.T) {
	p := os.Getenv("KM_RECOVERY_INPUT")
	if p == "" {
		t.Skip("explicit private snapshot required")
	}
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	if fmt.Sprintf("%x", sha256.Sum256(b)) != os.Getenv("KM_RECOVERY_SHA256") {
		t.Fatal("snapshot mismatch")
	}
	var d dictationMonthlyLedger
	if err = json.Unmarshal(b, &d); err != nil {
		t.Fatal(err)
	}
	if len(d.Entries) != 10 {
		t.Fatal("not exact stale cohort")
	}
	before, err := dictationMonthlyAccounted(&d, "2026-11")
	if err != nil || before != 10000000 {
		t.Fatal("unexpected prior accounting")
	}
	for i := range d.Entries {
		if d.Entries[i].OperatorRecovery != nil {
			t.Fatal("already recovered")
		}
		recoveryMark(&d.Entries[i])
	}
	after, err := dictationMonthlyAccounted(&d, "2026-11")
	if err != nil || after != 8000000 {
		t.Fatal("invalid candidate")
	}
	// Copy-only actual admission and settlement functions: no production writes.
	root := t.TempDir()
	month := time.Now().UTC().Format("2006-01")
	if month != "2026-11" {
		t.Fatal("operator window expired")
	}
	path := filepath.Join(root, "paid-months", month+".json")
	os.MkdirAll(filepath.Dir(path), 0700)
	candidate, _ := json.Marshal(d)
	if err = os.WriteFile(path, candidate, 0600); err != nil {
		t.Fatal(err)
	}
	one, err := dictationReserveMonthly(root)
	if err != nil {
		t.Fatal("first admission blocked", err)
	}
	if _, err = dictationReserveMonthly(root); err != nil {
		t.Fatal("second admission blocked", err)
	}
	if _, err = dictationReserveMonthly(root); err == nil {
		t.Fatal("cap exceeded")
	}
	if err = dictationRecordCompletedUsage(root, one, "synthetic-response-completed", *recoveryFixture(t).Usage); err != nil {
		t.Fatal(err)
	}
	if _, err = dictationReserveMonthly(root); err == nil {
		t.Fatal("nonzero new receipt ignored")
	}
	post, _ := os.ReadFile(path)
	var result dictationMonthlyLedger
	json.Unmarshal(post, &result)
	for i := 0; i < 10; i++ {
		a, _ := json.Marshal(d.Entries[i])
		z, _ := json.Marshal(result.Entries[i])
		if string(a) != string(z) {
			t.Fatal("historical record changed")
		}
	}
	out := os.Getenv("KM_RECOVERY_OUTPUT")
	if out == "" {
		t.Fatal("separate output required")
	}
	f, err := os.OpenFile(out, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = f.Write(candidate); err != nil {
		t.Fatal(err)
	}
	if err = f.Sync(); err != nil {
		t.Fatal(err)
	}
	f.Close()
	t.Logf("validated stale entries=10 before=%d unknown_reserve=%d released=%d cap=%d; copied-store admission and prospective settlement passed; no provider call", before, after, before-after, dictationMonthlyMicroUSD)
}
