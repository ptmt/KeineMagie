package main

// Settlement is server-only proof that a complete, bound final response was
// received. A historical usage estimate alone does not prove completion and
// cannot reduce a reservation. Never infer an owner from this global ledger.
type dictationSettlement struct {
	Version       int    `json:"version"`
	Currency      string `json:"currency"`
	Model         string `json:"model"`
	RateCard      string `json:"rate_card"`
	Status        string `json:"status"`
	ResponseID    string `json:"response_id"`
	Month         string `json:"month"`
	ReservationID string `json:"reservation_id"`
}

const dictationRateCard = "realtime-mini-2026-11-20"

// Receipt and settlement commit in the same fsync/rename transaction. A crash
// before it leaves the original hold; a crash after it permits only exact replay.
// Called only after the transport validates the matching completed response.
func dictationRecordCompletedUsage(root string, ticket dictationBudgetTicket, responseID string, u dictationSpeechUsage) error {
	cost, ok := dictationUsageMicroUSD(u)
	if !ok {
		return errDictationBudget
	}
	proof := dictationSettlement{Version: 1, Currency: "USD", Model: "gpt-realtime-2.1-mini", RateCard: dictationRateCard, Status: "completed", ResponseID: responseID, Month: ticket.month, ReservationID: ticket.id}
	return dictationMonthlyTransaction(root, ticket.month, func(d *dictationMonthlyLedger) error {
		if _, err := dictationMonthlyAccounted(d, ticket.month); err != nil {
			return err
		}
		for i := range d.Entries {
			v := &d.Entries[i]
			if v.ID != ticket.id {
				continue
			}
			if v.Usage != nil && (*v.Usage != u || v.ActualMicroUSD != cost) {
				return errDictationBudget
			}
			if v.Settlement != nil && *v.Settlement != proof {
				return errDictationBudget
			}
			v.Usage = &u
			v.ActualMicroUSD = cost
			v.Settlement = &proof
			_, err := dictationMonthlyAccounted(d, ticket.month)
			return err
		}
		return errDictationBudget
	})
}

// Pure accounting/dry-run: no writes, refunds, deletion, owner inference or
// provider calls. The original reservation remains immutable for audit/recovery.
func dictationMonthlyAccounted(d *dictationMonthlyLedger, month string) (int64, error) {
	var total int64
	ids, responses := map[string]bool{}, map[string]bool{}
	for _, v := range d.Entries {
		if v.ID == "" || ids[v.ID] || v.MicroUSD != dictationAttemptMicroUSD || v.ActualMicroUSD < 0 || (v.Usage != nil && v.Usage.incomplete) {
			return 0, errDictationBudget
		}
		ids[v.ID] = true
		charge, recoveryErr := dictationOperatorRecoveryCharge(v, month)
		if recoveryErr != nil {
			return 0, recoveryErr
		}
		if s := v.Settlement; s != nil {
			if s.Version != 1 || s.Currency != "USD" || s.Model != "gpt-realtime-2.1-mini" || s.RateCard != dictationRateCard || s.Status != "completed" || s.ResponseID == "" || len(s.ResponseID) > 256 || responses[s.ResponseID] || s.Month != month || s.ReservationID != v.ID || v.Usage == nil {
				return 0, errDictationBudget
			}
			cost, ok := dictationUsageMicroUSD(*v.Usage)
			// This application sends text only. Any new modality needs a new ceiling
			// and rate review, not an optimistic release against the old text ceiling.
			if !ok || v.Usage.Input.AudioTokens != 0 || cost != v.ActualMicroUSD || cost > v.MicroUSD {
				return 0, errDictationBudget
			}
			responses[s.ResponseID] = true
			charge = cost
		}
		if charge > dictationMonthlyMicroUSD-total {
			return 0, errDictationBudget
		}
		total += charge
	}
	return total, nil
}
