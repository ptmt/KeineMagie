package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestDictationMonthlyOversizedWritePreservesLedger(t *testing.T) {
	root := t.TempDir()
	ticket, err := dictationReserveMonthly(root)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(root, "paid-months", ticket.month+".json")
	before, _ := os.ReadFile(path)
	err = dictationMonthlyTransaction(root, ticket.month, func(d *dictationMonthlyLedger) error {
		d.Entries[0].ID = string(make([]byte, dictationMonthlyMaxBytes))
		return nil
	})
	if err == nil {
		t.Fatal("wrote unreadable oversized ledger")
	}
	after, _ := os.ReadFile(path)
	if string(before) != string(after) {
		t.Fatal("oversized write damaged history")
	}
}

func TestDictationSettlementRetainsMoreThanTenReceipts(t *testing.T) {
	root := t.TempDir()
	month := time.Now().UTC().Format("2006-01")
	var d dictationMonthlyLedger
	u := dictationSpeechUsage{InputTokens: 10}
	u.Input.TextTokens = 10
	cost, _ := dictationUsageMicroUSD(u)
	for i := 0; i < 200; i++ {
		id := fmt.Sprintf("old-%d", i)
		d.Entries = append(d.Entries, dictationMonthlyEntry{ID: id, MicroUSD: dictationAttemptMicroUSD, Usage: &u, ActualMicroUSD: cost, Settlement: &dictationSettlement{Version: 1, Currency: "USD", Model: "gpt-realtime-2.1-mini", RateCard: dictationRateCard, Status: "completed", ResponseID: id, Month: month, ReservationID: id}})
	}
	b, _ := json.Marshal(d)
	if len(b) <= 65536 {
		t.Fatal("fixture too small")
	}
	path := filepath.Join(root, "paid-months", month+".json")
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, b, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := dictationReserveMonthly(root); err != nil {
		t.Fatal("settled history hit obsolete ten-attempt storage bound", err)
	}
	after, _ := os.ReadFile(path)
	if err := json.Unmarshal(after, &d); err != nil {
		t.Fatal(err)
	}
	if len(d.Entries) != 201 {
		t.Fatal("historical receipts lost")
	}
}

func TestDictationSettlementRejectsMalformedEvidenceWithoutMutation(t *testing.T) {
	for _, mode := range []string{"negative-hold", "negative-cost", "overflow-detail", "incomplete-usage", "wrong-currency", "stale-month", "wrong-ticket", "duplicate-id", "duplicate-response", "cost-mismatch", "partial-status"} {
		t.Run(mode, func(t *testing.T) {
			root := t.TempDir()
			ticket, err := dictationReserveMonthly(root)
			if err != nil {
				t.Fatal(err)
			}
			u := dictationSpeechUsage{InputTokens: 10, OutputTokens: 20}
			u.Input.TextTokens = 10
			u.Output.AudioTokens = 20
			if err = dictationRecordCompletedUsage(root, ticket, "r", u); err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(root, "paid-months", ticket.month+".json")
			b, _ := os.ReadFile(path)
			var d dictationMonthlyLedger
			if err = json.Unmarshal(b, &d); err != nil {
				t.Fatal(err)
			}
			v := &d.Entries[0]
			switch mode {
			case "negative-hold":
				v.MicroUSD = -1
			case "negative-cost":
				v.ActualMicroUSD = -1
			case "overflow-detail":
				v.Usage.Input.TextTokens = 9223372036854775807
			case "wrong-currency":
				v.Settlement.Currency = "EUR"
			case "stale-month":
				v.Settlement.Month = "2000-01"
			case "wrong-ticket":
				v.Settlement.ReservationID = "foreign"
			case "duplicate-id":
				d.Entries = append(d.Entries, *v)
			case "duplicate-response":
				other := *v
				other.ID = "other"
				s := *v.Settlement
				s.ReservationID = "other"
				other.Settlement = &s
				d.Entries = append(d.Entries, other)
			case "cost-mismatch":
				v.ActualMicroUSD++
			case "partial-status":
				v.Settlement.Status = "incomplete"
			}
			b, _ = json.Marshal(d)
			if mode == "incomplete-usage" {
				b = []byte(`{"entries":[{"id":"old","reserved_micro_usd":1000000,"reported_usage":{"input_tokens":0,"output_tokens":0}}]}`)
			}
			if err = os.WriteFile(path, b, 0600); err != nil {
				t.Fatal(err)
			}
			if _, err = dictationReserveMonthly(root); err == nil {
				t.Fatal("invalid ledger admitted")
			}
			after, _ := os.ReadFile(path)
			if string(b) != string(after) {
				t.Fatal("invalid evidence rewritten")
			}
		})
	}
}

func TestDictationLegacyConflictsAndInvalidTicketKeepOriginal(t *testing.T) {
	root := t.TempDir()
	ticket, err := dictationReserveMonthly(root)
	if err != nil {
		t.Fatal(err)
	}
	u := dictationSpeechUsage{InputTokens: 10}
	u.Input.TextTokens = 10
	if err = dictationRecordUsage(root, ticket, u); err != nil {
		t.Fatal(err)
	}
	changed := u
	changed.InputTokens++
	changed.Input.TextTokens++
	if err = dictationRecordUsage(root, ticket, changed); err == nil {
		t.Fatal("conflicting historical receipt accepted")
	}
	if err = dictationRecordCompletedUsage(root, dictationBudgetTicket{month: "../escaped", id: ticket.id}, "r", u); err == nil {
		t.Fatal("invalid month accepted")
	}
	if _, err = os.Stat(filepath.Join(root, "escaped.json.lock")); !os.IsNotExist(err) {
		t.Fatal("invalid ticket touched filesystem", err)
	}
	for i := 0; i < 9; i++ {
		if _, err = dictationReserveMonthly(root); err != nil {
			t.Fatal(err)
		}
	}
	if _, err = dictationReserveMonthly(root); err == nil {
		t.Fatal("legacy receipt manufactured completion")
	}
}

func TestDictationSettlementAtomicIdempotentAndConflicts(t *testing.T) {
	root := t.TempDir()
	ticket, err := dictationReserveMonthly(root)
	if err != nil {
		t.Fatal(err)
	}
	u := dictationSpeechUsage{InputTokens: 10, OutputTokens: 20}
	u.Input.TextTokens = 10
	u.Output.AudioTokens = 20
	if err := dictationRecordCompletedUsage(root, ticket, "r-complete", u); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(root, "paid-months", ticket.month+".json")
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := dictationRecordCompletedUsage(root, ticket, "r-complete", u); err != nil {
		t.Fatal(err)
	}
	after, _ := os.ReadFile(path)
	if string(before) != string(after) {
		t.Fatal("retry changed receipt")
	}
	changed := u
	changed.OutputTokens++
	changed.Output.AudioTokens++
	if err := dictationRecordCompletedUsage(root, ticket, "r-complete", changed); err == nil {
		t.Fatal("conflicting usage accepted")
	}
	if err := dictationRecordCompletedUsage(root, ticket, "r-other", u); err == nil {
		t.Fatal("conflicting response accepted")
	}
	second, err := dictationReserveMonthly(root)
	if err != nil {
		t.Fatal(err)
	}
	if err := dictationRecordCompletedUsage(root, second, "r-complete", u); err == nil {
		t.Fatal("response reused across reservations")
	}
	var d dictationMonthlyLedger
	after, _ = os.ReadFile(path)
	if err := json.Unmarshal(after, &d); err != nil {
		t.Fatal(err)
	}
	cost, _ := dictationUsageMicroUSD(u)
	charged, err := dictationMonthlyAccounted(&d, ticket.month)
	if err != nil || charged != dictationAttemptMicroUSD+cost {
		t.Fatal(charged, err)
	}
}

// These are synthetic completed receipts, not reconstructed production evidence.
func TestDictationSettledTenReceiptsAdmitWithinUnchangedCap(t *testing.T) {
	root := t.TempDir()
	month := time.Now().UTC().Format("2006-01")
	entries := []map[string]any{}
	var total int64
	for i := 0; i < 10; i++ {
		tokens := int64(6740)
		if i == 9 {
			tokens = 6680
		}
		u := dictationSpeechUsage{InputTokens: tokens}
		u.Input.TextTokens = tokens
		cost, ok := dictationUsageMicroUSD(u)
		if !ok {
			t.Fatal("fixture")
		}
		total += cost
		id := fmt.Sprintf("synthetic-%d", i)
		entries = append(entries, map[string]any{"id": id, "reserved_micro_usd": dictationAttemptMicroUSD, "reported_usage": u, "reported_cost_micro_usd": cost, "settlement": map[string]any{"version": 1, "currency": "USD", "model": "gpt-realtime-2.1-mini", "rate_card": "realtime-mini-2026-11-20", "status": "completed", "response_id": "response-" + id, "month": month, "reservation_id": id}})
	}
	if total != 40404 {
		t.Fatal("fixture total", total)
	}
	b, _ := json.Marshal(map[string]any{"entries": entries})
	var preview dictationMonthlyLedger
	if err := json.Unmarshal(b, &preview); err != nil {
		t.Fatal(err)
	}
	completedCharge, err := dictationMonthlyAccounted(&preview, month)
	if err != nil || completedCharge != total {
		t.Fatal(completedCharge, err)
	}
	// Historical snapshots contain usage but no persisted response/status proof.
	// The dry-run must not manufacture that proof or assign an unknown owner.
	for i := range preview.Entries {
		preview.Entries[i].Settlement = nil
	}
	legacyBefore, _ := json.Marshal(preview)
	legacyCharge, err := dictationMonthlyAccounted(&preview, month)
	legacyAfter, _ := json.Marshal(preview)
	if err != nil || legacyCharge != dictationMonthlyMicroUSD || string(legacyBefore) != string(legacyAfter) {
		t.Fatal("unsafe historical preview", legacyCharge, err)
	}
	t.Logf("synthetic dry-run only: receipts=%d reported_micro_usd=%d completed_accounted_micro_usd=%d legacy_unproven_accounted_micro_usd=%d cap_micro_usd=%d; no production reads/writes", len(preview.Entries), total, completedCharge, legacyCharge, dictationMonthlyMicroUSD)
	path := filepath.Join(root, "paid-months", month+".json")
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, b, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := dictationReserveMonthly(root); err != nil {
		t.Fatal("ten completed receipts costing 40404 microUSD must not exhaust $10", err)
	}
	// Nine additional full holds fit; the tenth does not. No cap increase.
	for i := 0; i < 8; i++ {
		if _, err := dictationReserveMonthly(root); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := dictationReserveMonthly(root); err == nil {
		t.Fatal("exceeded unchanged $10 cap")
	}
	var got dictationMonthlyLedger
	b, err = os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal(b, &got); err != nil {
		t.Fatal(err)
	}
	if len(got.Entries) != 19 {
		t.Fatal("history erased", len(got.Entries))
	}
}
