package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"testing"
)

func TestDictationOperatorRecoveryUnknownCost(t *testing.T) {
	// Synthetic historical record, explicitly NOT a provider completion proof.
	raw := []byte(`{"entries":[{"id":"20261120T120000.000000000","reserved_micro_usd":1000000,"reported_usage":{"input_tokens":1,"output_tokens":1,"input_token_details":{"text_tokens":1,"audio_tokens":0,"image_tokens":0},"output_token_details":{"text_tokens":0,"audio_tokens":1}},"reported_cost_micro_usd":21,"operator_recovery":{"policy":"november-2026-unknown-cost-reserve-v1","reserve_micro_usd":800000,"original_sha256":"PLACEHOLDER","audit_id":"20261127-operator-authorized-stale-holds"}}]}`)
	var d dictationMonthlyLedger
	if err := json.Unmarshal(raw, &d); err != nil {
		t.Fatal(err)
	}
	// Populate digest without requiring the new Go schema to compile the RED test.
	original := d.Entries[0]
	original.OperatorRecovery = nil
	b, _ := json.Marshal(original)
	var wire map[string]any
	json.Unmarshal(raw, &wire)
	entry := wire["entries"].([]any)[0].(map[string]any)
	entry["operator_recovery"].(map[string]any)["original_sha256"] = fmt.Sprintf("%x", sha256.Sum256(b))
	raw, _ = json.Marshal(wire)
	json.Unmarshal(raw, &d)
	got, err := dictationMonthlyAccounted(&d, "2026-11")
	if err != nil || got != 800000 {
		t.Fatalf("unknown cost must retain nonzero operator reserve, got=%d err=%v", got, err)
	}
	if d.Entries[0].Settlement != nil || d.Entries[0].MicroUSD != 1000000 || d.Entries[0].ActualMicroUSD != 21 {
		t.Fatal("forged settlement or modified history")
	}
}
