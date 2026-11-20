package main

import (
	"encoding/json"
	"testing"
)

func TestDictationHierarchyProvenance(t *testing.T) {
	text := "Die kleine Katze schläft, weil sie sehr müde ist. Der Hund wartet."
	plan := dictationPacingPlan(text, nil, 2)
	data, _ := json.Marshal(plan)
	var rows []map[string]any
	_ = json.Unmarshal(data, &rows)
	want := [][2]float64{{1, 1}, {1, 1}, {1, 2}, {1, 2}, {2, 1}, {2, 1}}
	for i, pair := range want {
		if rows[i+1]["sentence"] != pair[0] || rows[i+1]["fragment"] != pair[1] {
			t.Errorf("step %d lacks exact sentence/fragment provenance: %v", i+1, rows[i+1])
		}
	}
	if len(plan) != 8 || plan[0].Kind != "whole" || plan[7].Kind != "final" {
		t.Fatal("hierarchy must not add audio steps")
	}
}

func TestDictationHierarchyPublicNeverLeaksSourceOrMutatesLegacy(t *testing.T) {
	text := "Die kleine Katze schläft, weil sie sehr müde ist. Der Hund wartet."
	plan := dictationPacingPlan(text, nil, 2)
	public := dictationPublic(dictationRecord{Text: text, Plan: plan}, false)
	for i, step := range public.Plan {
		if step.Text != "" {
			t.Fatal("source leaked")
		}
		if step.Sentence != plan[i].Sentence || step.Fragment != plan[i].Fragment {
			t.Fatal("provenance lost")
		}
	}
	if plan[1].Text == "" {
		t.Fatal("stored source mutated")
	}
	legacy := dictationPlan(text)
	before, _ := json.Marshal(legacy)
	public = dictationPublic(dictationRecord{Text: text, Plan: legacy}, false)
	for _, step := range public.Plan {
		if step.Sentence != 0 || step.Fragment != 0 {
			t.Fatal("invented legacy hierarchy")
		}
	}
	after, _ := json.Marshal(legacy)
	if string(before) != string(after) {
		t.Fatal("legacy changed")
	}
	repeated := dictationPacingPlan(text, plan, 3)
	for _, step := range repeated {
		for _, old := range plan {
			if step.Text == old.Text && step.Asset != old.Asset {
				t.Fatal("asset identity changed")
			}
		}
	}
}
