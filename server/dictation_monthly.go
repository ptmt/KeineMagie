package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"time"
)

// Official rates rechecked 2026-11-20. A conservative $1 hold exceeds the entire
// documented model envelope: 128k text input*$0.60/M + 32k output*$20/M
// = $0.7168. The actual session additionally caps output at <=4096 tokens.
// Uncertain calls retain the full hold. Only bound, completed response receipts
// settle to the pinned conservative token cost; original holds/history survive.
// This is an application admission guard, not a guarantee about provider billing,
// changed prices, taxes, other apps, or an invoice's posting month.
const dictationMonthlyMicroUSD int64 = 10_000_000
const dictationAttemptMicroUSD int64 = 1_000_000

// Bounded storage grows with retained receipts, not with dollars reserved.
const dictationMonthlyMaxBytes = 4 << 20

type dictationSpeechUsage struct {
	incomplete   bool
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
	OwnerHash      string                `json:"owner_hash,omitempty"`
	ID             string                `json:"id"`
	MicroUSD       int64                 `json:"reserved_micro_usd"`
	Usage          *dictationSpeechUsage `json:"reported_usage,omitempty"`
	ActualMicroUSD int64                 `json:"reported_cost_micro_usd,omitempty"`
	Settlement     *dictationSettlement  `json:"settlement,omitempty"`
}
type dictationMonthlyLedger struct {
	Entries []dictationMonthlyEntry `json:"entries"`
}
type dictationBudgetTicket struct{ month, id string }

func dictationMonthlyTransaction(root, month string, fn func(*dictationMonthlyLedger) error) error {
	parsed, err := time.Parse("2006-01", month)
	if err != nil || parsed.Format("2006-01") != month {
		return errDictationBudget
	}
	store := &historyStore{path: filepath.Join(root, "paid-months", month+".json")}
	return store.locked(func() error {
		d := dictationMonthlyLedger{}
		b, e := os.ReadFile(store.path)
		if e == nil {
			if len(b) > dictationMonthlyMaxBytes {
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
		encoded, err := json.Marshal(d)
		if err != nil {
			return err
		}
		if len(encoded) > dictationMonthlyMaxBytes {
			return errDictationBudget
		}
		return learningAtomicJSON(store.path, d)
	})
}
func dictationReserveMonthly(root string) (dictationBudgetTicket, error) {
	return dictationReserveMonthlyBefore(root, nil)
}

// Hold the monthly lock through the daily admission. Ordinary limit rejection
// changes neither allowance. A filesystem failure after the daily commit keeps
// that conservative reservation; no provider call is made until all commits pass.
func dictationReserveMonthlyBefore(root string, before func() error, owner ...string) (dictationBudgetTicket, error) {
	ticket := dictationBudgetTicket{month: time.Now().UTC().Format("2006-01")}
	err := dictationMonthlyTransaction(root, ticket.month, func(d *dictationMonthlyLedger) error {
		spent, err := dictationMonthlyAccounted(d, ticket.month)
		if err != nil {
			return err
		}
		if spent > dictationMonthlyMicroUSD-dictationAttemptMicroUSD {
			return errDictationBudget
		}
		if before != nil {
			if err := before(); err != nil {
				return err
			}
		}
		// The ledger lock and monotone length make this unique within a month.
		ticket.id = time.Now().UTC().Format("20060102T150405.000000000")
		ownerHash := ""
		if len(owner) == 1 && owner[0] != "" {
			ownerHash = sessionHash(owner[0])
		}
		d.Entries = append(d.Entries, dictationMonthlyEntry{ID: ticket.id, MicroUSD: dictationAttemptMicroUSD, OwnerHash: ownerHash})
		return nil
	})
	return ticket, err
}
func (u *dictationSpeechUsage) UnmarshalJSON(b []byte) error {
	type plain dictationSpeechUsage
	var decoded plain
	if err := json.Unmarshal(b, &decoded); err != nil {
		return err
	}
	var fields struct {
		Input  *int64 `json:"input_tokens"`
		Output *int64 `json:"output_tokens"`
		In     struct {
			Text  *int64 `json:"text_tokens"`
			Audio *int64 `json:"audio_tokens"`
		} `json:"input_token_details"`
		Out struct {
			Text  *int64 `json:"text_tokens"`
			Audio *int64 `json:"audio_tokens"`
		} `json:"output_token_details"`
	}
	if err := json.Unmarshal(b, &fields); err != nil {
		return err
	}
	*u = dictationSpeechUsage(decoded)
	u.incomplete = fields.Input == nil || fields.Output == nil || fields.In.Text == nil || fields.In.Audio == nil || fields.Out.Text == nil || fields.Out.Audio == nil
	return nil
}

func dictationUsageMicroUSD(u dictationSpeechUsage) (int64, bool) {
	if u.incomplete || u.Input.TextTokens > 128000 || u.Input.AudioTokens > 128000 || u.Output.TextTokens > 32000 || u.Output.AudioTokens > 32000 {
		return 0, false
	}
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
		if _, err := dictationMonthlyAccounted(d, ticket.month); err != nil {
			return err
		}
		for i := range d.Entries {
			v := &d.Entries[i]
			if v.ID == ticket.id {
				if v.Usage != nil {
					if *v.Usage != u || v.ActualMicroUSD != cost {
						return errDictationBudget
					}
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
