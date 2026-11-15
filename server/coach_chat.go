package main

import "time"

// Bounded private owner log: no text, sources, answers, or provider payloads.
type coachChatEvent struct {
	Type   string    `json:"type"`
	Count  int       `json:"count"`
	TurnID string    `json:"turn_id"`
	At     time.Time `json:"at"`
}

func coachMessageVersion(t *coachTurn) string {
	v := t.ID + ":" + t.State
	if t.Attempt != nil {
		v = t.ID + ":" + t.Attempt.ID + ":" + t.Attempt.AssessmentState
	}
	return v
}
func coachChatMutation(d *coachData, in coachInput, now time.Time) error {
	duplicate, e := coachReceiptExists(d, in)
	if e != nil || duplicate {
		return e
	}
	// Seen receipts replace a per-message revision; entry has a durable request receipt.
	if in.Action == "entry" {
		if len(d.Receipts) >= 10000 {
			return errCoachConflict
		}
		coachRecord(d, in)
		eligible := (d.LastVisit == nil || !now.Before(d.LastVisit.Add(5*time.Hour))) && (d.LastNudge == nil || !now.Before(d.LastNudge.Add(5*time.Hour)))
		d.LastVisit = &now
		for _, t := range d.Turns {
			if t.State == "pending" || (t.Attempt != nil && t.Attempt.AssessmentState == "pending") {
				eligible = false
			}
		}
		if eligible && coachActive(d) == nil && len(d.Turns) < 250 {
			offers := map[string]string{"en": "Have 30 seconds?", "ru": "Есть 30 секунд?", "de": "Hast du 30 Sekunden?", "es": "¿Tienes 30 segundos?", "fr": "Tu as 30 secondes ?"}
			message := offers[in.Locale]
			if message == "" {
				message = offers["en"]
			}
			d.Turns = append(d.Turns, coachTurn{ID: in.RequestID, State: "completed", Locale: in.Locale, At: now, Result: &coachResult{Kind: "nudge", Message: message}})
			d.LastNudge = &now
		}
		return nil
	}
	t := coachFind(d, in.TurnID)
	if t == nil || t.State != "completed" || t.Result == nil {
		return errCoachConflict
	}
	if in.Action == "seen" {
		if in.Text != coachMessageVersion(t) {
			return errCoachConflict
		}
		t.SeenVersion = in.Text
		return nil
	}
	if in.Action != "reveal" {
		return errCoachConflict
	}
	if len(d.Receipts) >= 10000 {
		return errCoachConflict
	}
	kind := in.Text
	if kind == "" {
		kind = "source"
	} // old clients
	switch kind {
	case "source":
		if t.Result.SourceID == "" || t.Result.Quote == "" || t.Result.Kind == "nudge" {
			return errCoachConflict
		}
		t.SourceReveals++
		if t.Attempt == nil {
			t.Assisted = true
		}
	case "answer":
		if t.Attempt == nil {
			return errCoachConflict
		}
		t.AnswerReveals++
	default:
		return errCoachConflict
	}
	count := t.SourceReveals
	if kind == "answer" {
		count = t.AnswerReveals
	}
	d.Events = append(d.Events, coachChatEvent{Type: kind, Count: count, TurnID: t.ID, At: now})
	if len(d.Events) > 512 {
		d.Events = append([]coachChatEvent(nil), d.Events[len(d.Events)-512:]...)
	}
	coachRecord(d, in)
	return nil
}
