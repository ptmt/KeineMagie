package main

import (
	"strings"
	"unicode"
)

// Pacing is a version-2 contract. It never changes policy-0/1 saved plans.
type dictationPacing struct {
	Repeats    int `json:"repeats"`
	GapSeconds int `json:"gap_seconds"`
}

// Policy-2 sentence boundaries protect abbreviations after opening quotes and
// compact German forms. Existing attempts retain their original plan verbatim.
func dictationPacingSentences(text string) []string {
	r := []rune(text)
	start := 0
	out := []string{}
	abbreviations := map[string]bool{"dr.": true, "prof.": true, "bzw.": true, "ca.": true, "nr.": true, "usw.": true, "etc.": true, "z.b.": true, "d.h.": true, "u.a.": true, "u.u.": true, "sog.": true, "vgl.": true}
	for i, c := range r {
		if c != '.' && c != '!' && c != '?' {
			continue
		}
		if c == '.' {
			if i > 0 && i+1 < len(r) && unicode.IsDigit(r[i-1]) && unicode.IsDigit(r[i+1]) {
				continue
			}
			j := i - 1
			for j >= start && (unicode.IsLetter(r[j]) || r[j] == '.') {
				j--
			}
			token := strings.ToLower(string(r[j+1 : i+1]))
			letters := []rune(token)
			if abbreviations[token] || (len(letters) == 2 && unicode.IsLetter(letters[0])) {
				continue
			}
		}
		end := i + 1
		for end < len(r) && strings.ContainsRune(".!?\"”’“»«)", r[end]) {
			end++
		}
		if end < len(r) && !unicode.IsSpace(r[end]) {
			continue
		}
		if end <= start {
			continue
		}
		if s := strings.TrimSpace(string(r[start:end])); s != "" {
			out = append(out, s)
		}
		start = end
	}
	if s := strings.TrimSpace(string(r[start:])); s != "" {
		out = append(out, s)
	}
	return out
}

// Conservative punctuation heuristic, not semantic parsing. Lists, decimals,
// short tails and punctuation inside quotes are deliberately not clause cuts.
func dictationFragments(text string) []string {
	out := []string{}
	for _, sentence := range dictationPacingSentences(text) {
		r := []rune(sentence)
		start := 0
		quoted := false
		for i, c := range r {
			if strings.ContainsRune("\"„“”«»", c) {
				quoted = !quoted
				continue
			}
			if quoted || (c != ',' && c != ';' && c != ':' && c != '—') {
				continue
			}
			left, right := strings.TrimSpace(string(r[start:i+1])), strings.TrimSpace(string(r[i+1:]))
			if len(strings.Fields(left)) < 3 || len(strings.Fields(right)) < 3 {
				continue
			}
			if c == ',' {
				first := strings.ToLower(strings.Fields(right)[0])
				switch first {
				case "weil", "obwohl", "wenn", "während", "damit", "sodass", "aber", "denn", "sondern", "dass", "bevor", "nachdem", "falls":
				default:
					continue
				}
			}
			// Colon/dash without whitespace is likely a number, URL or compound.
			if c != ';' && c != ',' && (i+1 >= len(r) || !unicode.IsSpace(r[i+1])) {
				continue
			}
			out = append(out, left)
			start = i + 1
		}
		if tail := strings.TrimSpace(string(r[start:])); tail != "" {
			out = append(out, tail)
		}
	}
	return out
}

// An extra replay is one deliberate replay of a fully completed fragment. It
// does not replace a planned repetition, advance the cursor, or consume whole starts.
func dictationCanReplay(v dictationRecord, step int) bool {
	if v.Mode != "sentences" || step < 1 || step >= len(v.Plan)-1 || v.Plan[step].Kind != "sentence" || step >= v.Playback.Cursor {
		return false
	}
	for i := step; i < len(v.Plan)-1; i++ {
		if i > step && v.Plan[i].Kind != "sentence_repeat" {
			break
		}
		complete := false
		for _, a := range v.Playback.Listens {
			if a.Step == i && a.Ended && !a.Stopped && a.Intent == "planned" {
				complete = true
				break
			}
		}
		if !complete {
			return false
		}
	}
	return true
}

// Reuse exact existing text identities. Newly split assets receive new IDs;
// callers never replace existing bytes or implicitly synthesize missing audio.
func dictationPacingPlan(text string, previous []dictationSegment, repeats int) []dictationSegment {
	assets := map[string]int{text: 0}
	next := 1
	for _, s := range previous {
		assets[s.Text] = s.Asset
		if s.Asset >= next {
			next = s.Asset + 1
		}
	}
	out := []dictationSegment{{Kind: "whole", Text: text, Asset: 0}}
	for sentenceIndex, sentence := range dictationPacingSentences(text) {
		for fragmentIndex, fragment := range dictationFragments(sentence) {
			asset, ok := assets[fragment]
			if !ok {
				asset = next
				next++
				assets[fragment] = asset
			}
			for repeat := 0; repeat < repeats; repeat++ {
				kind := "sentence"
				if repeat > 0 {
					kind = "sentence_repeat"
				}
				out = append(out, dictationSegment{Kind: kind, Text: fragment, Asset: asset, Sentence: sentenceIndex + 1, Fragment: fragmentIndex + 1})
			}
		}
	}
	return append(out, dictationSegment{Kind: "final", Text: text, Asset: 0})
}
