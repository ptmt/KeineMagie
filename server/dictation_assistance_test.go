package main

import "testing"

func TestDictationAssistancePolicyTwoAcceptedEvidence(t *testing.T) {
	// Synthetic wire fixture matches pacing candidate ec47272's actual tagged DTO.
	raw := []byte(`{"playback_policy_version":2,"plan":[{"kind":"whole","asset":0},{"kind":"sentence","asset":1},{"kind":"sentence_repeat","asset":1},{"kind":"final","asset":0}],"playback":{"listens":[{"id":"a","policy_version":2,"step":1,"asset":1,"intent":"planned","ended":true},{"id":"b","policy_version":2,"step":2,"asset":1,"intent":"planned","stopped":true,"interruptions":1,"resumes":2},{"id":"c","policy_version":2,"step":1,"asset":1,"intent":"extra","ended":true},{"id":"c","policy_version":2,"step":1,"asset":1,"intent":"extra","ended":true}]}}`)
	a := dictationAssistanceFromWire(raw)
	if a.Tracking != "partial" || len(a.Segments) != 1 {
		t.Fatal(a)
	}
	s := a.Segments[0]
	if s.PlannedRepetitions != 2 || s.ExtraRequested != 1 || s.Started != 3 || s.Completed != 2 || s.Stopped != 1 || s.Resumes != 2 || s.Interruptions != 1 {
		t.Fatal(s)
	}
}
func TestDictationAssistanceLegacyRemainsUnknown(t *testing.T) {
	a := dictationAssistanceFromWire([]byte(`{"playback_policy_version":1,"playback":{"listens":[{"id":"a","step":1,"done":true}]}}`))
	if a.Tracking != "unknown" || len(a.Segments) != 0 {
		t.Fatal(a)
	}
	a = dictationAssistanceFromWire([]byte(`{"playback_policy_version":2,"pacing_history":{"policy_version":1},"plan":[],"playback":{"listens":[{"id":"old","step":1,"done":true}]}}`))
	if !a.ArchivedUnknown || a.UnknownAdmissions != 1 || len(a.Segments) != 0 {
		t.Fatal(a)
	}
}
