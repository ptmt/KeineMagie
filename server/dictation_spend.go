package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

// Temporary receipt display, not an invoice or all-AI total. Historical global
// receipts have no owner attribution and are intentionally never exposed here.
type dictationSpeechSpend struct {
	Month                 string `json:"month"`
	Currency              string `json:"currency"`
	Scope                 string `json:"scope"`
	ReportedMicroUSD      *int64 `json:"reported_micro_usd"`
	UnsettledReservations int    `json:"unsettled_reservations"`
	ReservedMicroUSD      int64  `json:"reserved_micro_usd"`
}

func (cfg *serverConfig) dictationSpeechSpend(owner string) dictationSpeechSpend {
	out := dictationSpeechSpend{Month: time.Now().UTC().Format("2006-01"), Currency: "USD", Scope: "owner_attributed_speech_receipts"}
	root := filepath.Join(filepath.Dir(cfg.historyPath), "dictations")
	store := &historyStore{path: filepath.Join(root, "paid-months", out.Month+".json")}
	err := store.locked(func() error {
		b, e := os.ReadFile(store.path)
		if os.IsNotExist(e) {
			return nil
		}
		if e != nil {
			return e
		}
		if len(b) > 65536 {
			return errDictationBudget
		}
		var ledger dictationMonthlyLedger
		if e = json.Unmarshal(b, &ledger); e != nil {
			return e
		}
		total := int64(0)
		receipts := 0
		for _, entry := range ledger.Entries {
			if entry.OwnerHash != sessionHash(owner) {
				continue
			}
			out.ReservedMicroUSD += entry.MicroUSD
			if entry.Usage == nil {
				out.UnsettledReservations++
				continue
			}
			cost, ok := dictationUsageMicroUSD(*entry.Usage)
			if !ok || cost != entry.ActualMicroUSD {
				out.UnsettledReservations++
				continue
			}
			receipts++
			total += cost
		}
		if receipts > 0 {
			out.ReportedMicroUSD = &total
		}
		return nil
	})
	if err != nil {
		out.ReportedMicroUSD = nil
		out.UnsettledReservations = 0
		out.ReservedMicroUSD = 0
	}
	return out
}
