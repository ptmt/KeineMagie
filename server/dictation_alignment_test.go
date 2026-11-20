package main

import (
	"strings"
	"testing"
)

func TestDictationAlignmentLiteralOffsetsAndBoundedSuffix(t *testing.T) {
	for _, v := range []struct {
		source, answer string
		complete       bool
	}{
		{"  Ein Café.\nDanach bleibt er zu Hause.  ", " Ein Cafe\u0301. ", false},
		{"Heute, gehen wir heim.", "Heute gehen, wir heim.", true},
		{"Die kleine Katze schläft. " + strings.Repeat("Danach geht sie heim. ", 14), "Die Katze schläft.", false},
		{"Ja ja, heute ja.", "Ja ja.", false},
		{"Die Katze schläft.", "Etwas völlig anderes!", true},
		{"Die Katze schläft.", "", false},
	} {
		a := dictationAlign(v.source, v.answer, v.complete)
		source, answer := "", ""
		lastSource, lastAnswer := 0, 0
		suffixes := 0
		for _, s := range a.Spans {
			if s.SourceStart != lastSource || s.AnswerStart != lastAnswer || s.Original != v.source[s.SourceStart:s.SourceEnd] || s.Written != v.answer[s.AnswerStart:s.AnswerEnd] {
				t.Fatalf("bad literal offset: %+v", s)
			}
			lastSource, lastAnswer = s.SourceEnd, s.AnswerEnd
			source += s.Original
			answer += s.Written
			if s.Kind == "unattempted" {
				suffixes++
			}
		}
		if source != v.source || answer != v.answer || suffixes > 1 {
			t.Fatalf("reconstruction or flooding: %+v", a)
		}
		if a.AttemptedWords+a.UnattemptedWords != a.SourceWords {
			t.Fatalf("coverage mismatch: %+v", a)
		}
	}
}
func TestDictationAlignmentCompleteAndPunctuation(t *testing.T) {
	complete := dictationAlign("Die Katze schläft. Danach geht sie heim.", "Die Katze schläft.", true)
	if complete.Omissions != 4 || complete.UnattemptedWords != 0 {
		t.Fatal(complete)
	}
	partial := dictationAlign("Die kleine Katze schläft. Danach geht sie heim.", "Die Katze schläft.", false)
	for _, s := range partial.Spans {
		if s.Kind == "punctuation" {
			t.Fatal("missing word shifted punctuation", s)
		}
	}
}

func TestDictationAlignmentTerminalPunctuationIsNotUnattempted(t *testing.T) {
	a := dictationAlign("Die Katze.", "Die Katze", false)
	if a.Spans[len(a.Spans)-1].Kind != "punctuation" {
		t.Fatal(a)
	}
}

func TestDictationAlignmentCanonicalUnicodeIsNotAMistake(t *testing.T) {
	a := dictationAlign("Ein Café.", "Ein Cafe\u0301.", true)
	if a.Substitutions != 0 || a.ExactWords != 2 {
		t.Fatalf("Unicode encoding is not spelling: %+v", a)
	}
}

func TestDictationAlignmentInterruptedSuffix(t *testing.T) {
	a := dictationAlign("Die kleine Katze schläft. Danach geht sie nach Hause.", "Die Katze schläft.", false)
	if a.UnattemptedWords != 5 || a.Omissions != 1 {
		t.Fatalf("unfinished suffix is not omission: %+v", a)
	}
	var original, answer string
	for _, s := range a.Spans {
		original += s.Original
		answer += s.Written
	}
	if original != "Die kleine Katze schläft. Danach geht sie nach Hause." || answer != "Die Katze schläft." {
		t.Fatalf("literal reconstruction: %q / %q", original, answer)
	}
}
