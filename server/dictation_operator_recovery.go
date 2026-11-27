package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"time"
)

// Operator recovery is NOT provider settlement or a final-cost claim. It retains
// $0.80 unknown-cost reserve per exact historical $1 entry, with original data
// immutable. No HTTP API creates this field; only a locked offline operator tool
// may install it after user authorization and an immutable private snapshot.
// This one-time November policy cannot affect newly admitted calls or owners.
type dictationOperatorRecovery struct {
	Policy          string `json:"policy"`
	ReserveMicroUSD int64  `json:"reserve_micro_usd"`
	OriginalSHA256  string `json:"original_sha256"`
	AuditID         string `json:"audit_id"`
}

func dictationOperatorRecoveryCharge(v dictationMonthlyEntry, month string) (int64, error) {
	r := v.OperatorRecovery
	if r == nil {
		return v.MicroUSD, nil
	}
	when, err := time.Parse("20060102T150405.000000000", v.ID)
	if err != nil || when.Format("2006-01") != "2026-11" || !when.Before(time.Date(2026, 11, 21, 0, 0, 0, 0, time.UTC)) || month != "2026-11" || r.Policy != "november-2026-unknown-cost-reserve-v1" || r.AuditID != "20261127-operator-authorized-stale-holds" || r.ReserveMicroUSD != 800000 || v.OwnerHash != "" || v.Settlement != nil || v.MicroUSD != dictationAttemptMicroUSD || v.Usage == nil {
		return 0, errDictationBudget
	}
	cost, ok := dictationUsageMicroUSD(*v.Usage)
	if !ok || v.Usage.Input.AudioTokens != 0 || cost <= 0 || cost != v.ActualMicroUSD || cost > r.ReserveMicroUSD {
		return 0, errDictationBudget
	}
	v.OperatorRecovery = nil
	b, err := json.Marshal(v)
	if err != nil || fmt.Sprintf("%x", sha256.Sum256(b)) != r.OriginalSHA256 {
		return 0, errDictationBudget
	}
	return r.ReserveMicroUSD, nil
}
