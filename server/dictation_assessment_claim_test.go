package main

import "testing"

func TestDictationAssessmentRejectsUnsupportedLevel(t *testing.T) {
	a := dictationAlign("Die Katze.", "Die Katze.", true)
	_, e := decodeDictationAssessment(`{"notes":[{"span_id":"s0","category":"grammar","source_quote":"Die Katze.","answer_quote":"Die Katze.","explanation":"You are at CEFR C2."}]}`, a)
	if e == nil {
		t.Fatal("unsupported global level accepted")
	}
}
