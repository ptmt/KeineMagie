package main

import (
	"net/http"
	"time"
)

// A claim is persisted before catalog/quota/provider work. It is never leased or
// automatically retried: an uncertain upstream acceptance must not spend twice.
// The first authenticated opt-in pins one OWNER time zone, not one per device.
// Device zone differences therefore cannot create a second daily entitlement.
type coachDailyClaim struct {
	Day    string `json:"day"`
	TurnID string `json:"turn_id"`
}

func (cfg *serverConfig) coachDailyEntry(w http.ResponseWriter, r *http.Request, owner string, in coachInput) {
	if len(in.TimeZone) > 100 || in.TimeZone == "Local" {
		coachFailure(w, 400, "invalid", "invalid time zone")
		return
	}
	if _, e := time.LoadLocation(in.TimeZone); e != nil {
		coachFailure(w, 400, "invalid", "invalid time zone")
		return
	}
	admitted := false
	e := cfg.coachWrite(r, owner, func(d *coachData) error {
		duplicate, e := coachReceiptExists(d, in)
		if e != nil || duplicate {
			return e
		}
		if len(d.Receipts) >= 10000 {
			return errCoachConflict
		}
		if d.DailyTimeZone == "" {
			d.DailyTimeZone = in.TimeZone
		}
		zone, e := time.LoadLocation(d.DailyTimeZone)
		if e != nil {
			return e
		}
		now := cfg.auth.now()
		day := now.In(zone).Format("2006-01-02")
		coachRecord(d, in)
		for _, c := range d.DailyClaims {
			if c.Day == day {
				return nil
			}
		}
		if len(d.DailyClaims) >= 10000 {
			return errCoachConflict
		}
		// A cancel arriving ahead of admission is authoritative.
		if t := coachFind(d, in.RequestID); t != nil {
			return nil
		}
		resume := ""
		for _, t := range d.Turns {
			if t.State == "pending" || t.Attempt != nil && t.Attempt.AssessmentState != "" && t.Attempt.AssessmentState != "completed" {
				resume = t.ID
				break
			}
		}
		if resume == "" {
			if t := coachActive(d); t != nil {
				resume = t.ID
			}
		}
		if resume != "" {
			d.DailyClaims = append(d.DailyClaims, coachDailyClaim{day, resume})
			return nil
		}
		if len(d.Turns) >= 250 {
			return errCoachConflict
		}
		d.DailyClaims = append(d.DailyClaims, coachDailyClaim{day, in.RequestID})
		d.Turns = append(d.Turns, coachTurn{ID: in.RequestID, Locale: in.Locale, State: "pending", At: now.UTC()})
		admitted = true
		return nil
	})
	if e != nil {
		coachError(w, e)
		return
	}
	if !admitted {
		cfg.coachRead(w, owner)
		return
	}
	// A normal early preflight failure becomes a durable failed turn. A process
	// death leaves pending/uncertain; either state keeps today's claim consumed.
	defer func() {
		_ = cfg.coachWrite(r, owner, func(d *coachData) error {
			if t := coachFind(d, in.RequestID); t != nil && t.State == "pending" {
				t.State = "failed"
			}
			return nil
		})
	}()
	in.dailyAdmission = true
	cfg.coachMessage(w, r, owner, in)
}
