package main

import (
	"encoding/json"
	"path/filepath"
	"testing"
	"time"
)

func TestDictationSpendReportedReceiptsOnly(t *testing.T) {
	f := newPlaybackFixture(t)
	root := filepath.Join(filepath.Dir(f.cfg.historyPath), "dictations")
	ticket, e := dictationReserveMonthlyBefore(root, nil, f.owner)
	if e != nil {
		t.Fatal(e)
	}
	var usage dictationSpeechUsage
	usage.InputTokens = 10
	usage.Input.TextTokens = 10
	usage.OutputTokens = 20
	usage.Output.AudioTokens = 20
	if e = dictationRecordUsage(root, ticket, usage); e != nil {
		t.Fatal(e)
	}
	if _, e = dictationReserveMonthlyBefore(root, nil, f.owner); e != nil {
		t.Fatal(e)
	}
	if _, e = dictationReserveMonthlyBefore(root, nil, "other-owner"); e != nil {
		t.Fatal(e)
	}
	got := f.cfg.dictationSpeechSpend(f.owner)
	cost, _ := dictationUsageMicroUSD(usage)
	if got.ReportedMicroUSD == nil || *got.ReportedMicroUSD != cost || got.UnsettledReservations != 1 || got.ReservedMicroUSD != 2*dictationAttemptMicroUSD {
		t.Fatalf("wrong owner receipt aggregate: %+v", got)
	}
}

func TestDictationSpendIsOwnerScopedAndUnknownIsNotZero(t *testing.T) {
	f := newPlaybackFixture(t)
	root := filepath.Join(filepath.Dir(f.cfg.historyPath), "dictations")
	month := time.Now().UTC().Format("2006-01")
	if e := dictationMonthlyTransaction(root, month, func(d *dictationMonthlyLedger) error {
		return json.Unmarshal([]byte(`{"entries":[{"id":"old","reserved_micro_usd":1000000,"reported_cost_micro_usd":40404},{"id":"foreign","owner_hash":"foreign","reserved_micro_usd":1000000,"reported_cost_micro_usd":999}]}`), d)
	}); e != nil {
		t.Fatal(e)
	}
	w := f.call("GET", "", "")
	var v map[string]json.RawMessage
	json.Unmarshal(w.Body.Bytes(), &v)
	if len(v["speech_spend"]) == 0 {
		t.Fatal("missing owner-scoped speech spend")
	}
	var spend struct {
		Reported  *int64 `json:"reported_micro_usd"`
		Unsettled int    `json:"unsettled_reservations"`
	}
	json.Unmarshal(v["speech_spend"], &spend)
	if spend.Reported != nil || spend.Unsettled != 0 {
		t.Fatalf("global spend leaked or missing shown as zero: %s", v["speech_spend"])
	}
}
