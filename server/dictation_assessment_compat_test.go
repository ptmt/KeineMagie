package main

import (
	"encoding/json"
	"testing"
)

func TestDictationLegacyProjectionDoesNotPenalizeSuffix(t *testing.T) {
	f := newAssessmentFixture(t)
	seedDictationAssessment(t, f)
	w := dictationAssessmentCall(f, "POST", "/dict/check", `{"revision":1}`)
	var record dictationRecord
	if e := json.Unmarshal(w.Body.Bytes(), &record); e != nil {
		t.Fatal(e)
	}
	if len(record.Differences) != 1 || record.Differences[0].Kind != "missing" || record.Differences[0].Original != " kleine" {
		t.Fatalf("unfinished suffix leaked into legacy progress: %+v", record.Differences)
	}
}
