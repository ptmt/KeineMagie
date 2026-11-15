package main

import "strings"

func coachMessageIntent(text string) string {
	switch strings.ToLower(strings.TrimSpace(text)) {
	case "мой прогресс", "фидбек", "my progress", "feedback", "mein fortschritt", "mi progreso", "mes progrès":
		return "progress"
	case "ещё", "еще", "more", "noch eins", "otro", "encore":
		return "more"
	}
	return "message"
}

// Actions are derived from durable owner state, never from translated message text.
type coachQuickAction struct {
	Action string `json:"action"`
	TurnID string `json:"turn_id"`
}

func coachActive(d *coachData) *coachTurn {
	for i := len(d.Turns) - 1; i >= 0; i-- {
		t := &d.Turns[i]
		if t.State == "completed" && t.Result != nil && t.Attempt == nil && t.Result.Kind != "clarification" && t.Result.Kind != "nudge" {
			return t
		}
	}
	return nil
}
func coachActions(d *coachData) []coachQuickAction {
	out := []coachQuickAction{}
	for _, t := range d.Turns {
		if t.State == "pending" || t.Attempt != nil && t.Attempt.AssessmentState == "pending" {
			return out
		}
	}
	if t := coachActive(d); t != nil {
		if t.Result.SourceID != "" && t.SourceReveals == 0 {
			out = append(out, coachQuickAction{"reveal", t.ID})
		}
		return append(out, coachQuickAction{"progress", ""})
	}
	if len(d.Turns) == 0 {
		return append(out, coachQuickAction{"practice", ""})
	}
	t := d.Turns[len(d.Turns)-1]
	if t.State == "failed" || t.State == "canceled" {
		return append(out, coachQuickAction{"more", ""}, coachQuickAction{"progress", ""})
	}
	if t.Result != nil && t.Result.Kind == "nudge" {
		return append(out, coachQuickAction{"practice", ""})
	}
	if t.Attempt != nil && t.Attempt.AssessmentState != "" && t.Attempt.AssessmentState != "completed" {
		return append(out, coachQuickAction{"progress", ""})
	}
	if t.Attempt != nil && (t.Attempt.Outcome == "wrong" || t.Attempt.Outcome == "ambiguous") {
		out = append(out, coachQuickAction{"explain", t.ID})
	}
	return append(out, coachQuickAction{"more", ""}, coachQuickAction{"progress", ""})
}
func coachIsMessage(action string) bool {
	switch action {
	case "message", "practice", "more", "explain", "progress":
		return true
	}
	return false
}
