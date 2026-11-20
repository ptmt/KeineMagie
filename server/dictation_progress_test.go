package main

import "testing"

func TestDictationProgressFullCoverageIsNotPartialWithoutDeclaration(t *testing.T) {
	a := dictationAssessmentReceipt{Source: "Die Katze.", Alignment: dictationAlign("Die Katze.", "Die Katze.", false)}
	p := dictationProgress([]dictationRecord{{ID: "full", Checked: true, Assessment: &a}})
	if p.PartialAttempts != 0 {
		t.Fatal("full coverage called partial", p)
	}
}
func TestDictationProgressKeepsPartialCoverageAndDistinctExamples(t *testing.T) {
	a := dictationAssessmentReceipt{At: "2026-01-01T12:00:00Z", Alignment: dictationAlign("Die Katze schläft. Danach geht sie heim.", "Die Katze schläft.", false), ReplayTracking: "unknown"}
	records := []dictationRecord{{ID: "one", TextID: "same", Checked: true, Assessment: &a}, {ID: "two", TextID: "same", Checked: true, Assessment: &a}, {ID: "old", Checked: true}}
	p := dictationProgress(records)
	if p.Attempts != 2 || p.DistinctSources != 1 || p.PartialAttempts != 2 || p.LegacyUnknown != 1 || p.ExactWords != 6 || p.AttemptedWords != 6 || p.SourceWords != 14 || p.ReplayUnknown != 2 {
		t.Fatalf("misleading progress: %+v", p)
	}
}
