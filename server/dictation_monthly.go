package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"time"
)

// Official rates checked 2026-11-14. A conservative $1 hold exceeds the entire
// documented model envelope: 128k text input*$0.60/M + 32k output*$20/M
// = $0.7168. The actual session additionally caps output at <=4096 tokens.
// Holds NEVER release automatically: max ten generation attempts/UTC month.
// This is an application admission guard, not a guarantee about provider billing,
// changed prices, taxes, other apps, or an invoice's posting month.
const dictationMonthlyMicroUSD int64 = 10_000_000
const dictationAttemptMicroUSD int64 = 1_000_000

type dictationSpeechUsage struct {
	InputTokens  int64 `json:"input_tokens"`
	OutputTokens int64 `json:"output_tokens"`
	Input        struct {
		TextTokens  int64 `json:"text_tokens"`
		AudioTokens int64 `json:"audio_tokens"`
		ImageTokens int64 `json:"image_tokens"`
	} `json:"input_token_details"`
	Output struct {
		TextTokens  int64 `json:"text_tokens"`
		AudioTokens int64 `json:"audio_tokens"`
	} `json:"output_token_details"`
}
type dictationMonthlyEntry struct {
	ID             string                `json:"id"`
	MicroUSD       int64                 `json:"reserved_micro_usd"`
	Usage          *dictationSpeechUsage `json:"reported_usage,omitempty"`
	ActualMicroUSD int64                 `json:"reported_cost_micro_usd,omitempty"`
}
type dictationMonthlyLedger struct {
	Entries []dictationMonthlyEntry `json:"entries"`
}
type dictationBudgetTicket struct{ month, id string }

func dictationMonthlyTransaction(root, month string, fn func(*dictationMonthlyLedger) error) error {
	store := &historyStore{path: filepath.Join(root, "paid-months", month+".json")}
	return store.locked(func() error {
		d := dictationMonthlyLedger{}
		b, e := os.ReadFile(store.path)
		if e == nil {
			if len(b) > 65536 {
				return errDictationBudget
			}
			if e = json.Unmarshal(b, &d); e != nil {
				return e
			}
		} else if !errors.Is(e, os.ErrNotExist) {
			return e
		}
		if e = fn(&d); e != nil {
			return e
		}
		return learningAtomicJSON(store.path, d)
	})
}
func dictationReserveMonthly(root string) (dictationBudgetTicket, error) {
	ticket := dictationBudgetTicket{month: time.Now().UTC().Format("2006-01")}
	err := dictationMonthlyTransaction(root, ticket.month, func(d *dictationMonthlyLedger) error {
		var spent int64
		if len(d.Entries) >= 10 {
			return errDictationBudget
		}
		for _, v := range d.Entries {
			if v.MicroUSD != dictationAttemptMicroUSD {
				return errDictationBudget
			}
			spent += v.MicroUSD
		}
		if spent > dictationMonthlyMicroUSD-dictationAttemptMicroUSD {
			return errDictationBudget
		}
		// The ledger lock and monotone length make this unique within a month.
		ticket.id = time.Now().UTC().Format("20060102T150405.000000000")
		d.Entries = append(d.Entries, dictationMonthlyEntry{ID: ticket.id, MicroUSD: dictationAttemptMicroUSD})
		return nil
	})
	return ticket, err
}
func dictationUsageMicroUSD(u dictationSpeechUsage) (int64, bool) {
	if u.InputTokens < 0 || u.InputTokens > 128000 || u.OutputTokens < 0 || u.OutputTokens > 32000 || u.Input.TextTokens < 0 || u.Input.AudioTokens < 0 || u.Input.ImageTokens != 0 || u.Output.TextTokens < 0 || u.Output.AudioTokens < 0 {
		return 0, false
	}
	if u.Input.TextTokens+u.Input.AudioTokens != u.InputTokens || u.Output.TextTokens+u.Output.AudioTokens != u.OutputTokens {
		return 0, false
	}
	// Tenths of a micro-dollar avoid floats. Ignore cache discounts conservatively.
	cost := u.Input.TextTokens*6 + u.Input.AudioTokens*100 + u.Output.TextTokens*24 + u.Output.AudioTokens*200
	return (cost + 9) / 10, true
}
func dictationRecordUsage(root string, ticket dictationBudgetTicket, u dictationSpeechUsage) error {
	cost, ok := dictationUsageMicroUSD(u)
	if !ok {
		return errDictationBudget
	}
	return dictationMonthlyTransaction(root, ticket.month, func(d *dictationMonthlyLedger) error {
		for i := range d.Entries {
			v := &d.Entries[i]
			if v.ID == ticket.id {
				if v.Usage != nil {
					return nil
				}
				v.Usage = &u
				v.ActualMicroUSD = cost
				return nil
			}
		}
		return errDictationBudget
	})
}
