package main

import (
	"fmt"
	"golang.org/x/text/unicode/norm"
	"regexp"
	"strings"
)

// Offsets are UTF-8 byte offsets into the EXACT persisted strings, never NFC
// offsets. Normalization is only used for alignment costs, not evidence.
type dictationSpan struct {
	ID          string `json:"id"`
	Kind        string `json:"kind"`
	SourceStart int    `json:"source_start"`
	SourceEnd   int    `json:"source_end"`
	AnswerStart int    `json:"answer_start"`
	AnswerEnd   int    `json:"answer_end"`
	Original    string `json:"original"`
	Written     string `json:"written"`
}
type dictationAlignment struct {
	Version          int             `json:"version"`
	Complete         bool            `json:"complete"`
	Spans            []dictationSpan `json:"spans"`
	SourceWords      int             `json:"source_words"`
	AttemptedWords   int             `json:"attempted_words"`
	ExactWords       int             `json:"exact_words"`
	Omissions        int             `json:"omissions"`
	Additions        int             `json:"additions"`
	Substitutions    int             `json:"substitutions"`
	UnattemptedWords int             `json:"unattempted_words"`
}

var dictationTokens = regexp.MustCompile(`[\p{L}\p{M}\p{N}]+(?:['’][\p{L}\p{M}\p{N}]+)*|[^\s]`)

type dictationToken struct {
	start, end int
	text       string
	word       bool
}

func dictationTokenize(s string) []dictationToken {
	out := []dictationToken{}
	previous := 0
	for _, p := range dictationTokens.FindAllStringIndex(s, -1) {
		out = append(out, dictationToken{previous, p[1], s[p[0]:p[1]], dictationWords.MatchString(s[p[0]:p[1]])})
		previous = p[1]
	}
	if len(out) > 0 {
		out[len(out)-1].end = len(s)
	}
	return out
}
func dictationTokenEqual(a, b string) bool {
	return strings.EqualFold(norm.NFC.String(a), norm.NFC.String(b))
}

// Prefix alignment intentionally leaves an unattempted suffix unless the learner
// explicitly declares completion. It does not infer listened coverage from audio.
func dictationAlign(source, answer string, complete bool) dictationAlignment {
	a, b := dictationTokenize(source), dictationTokenize(answer)
	out := dictationAlignment{Version: 1, Complete: complete, Spans: []dictationSpan{}, SourceWords: len(dictationWords.FindAllString(source, -1))}
	d := make([][]int, len(a)+1)
	for i := range d {
		d[i] = make([]int, len(b)+1)
		d[i][0] = i
	}
	for j := range d[0] {
		d[0][j] = j
	}
	for i := 1; i <= len(a); i++ {
		for j := 1; j <= len(b); j++ {
			cost := 1
			if dictationTokenEqual(a[i-1].text, b[j-1].text) {
				cost = 0
			}
			d[i][j] = min(d[i-1][j]+1, d[i][j-1]+1, d[i-1][j-1]+cost)
		}
	}
	end := len(a)
	if !complete {
		end = 0
		for i := 1; i <= len(a); i++ {
			if d[i][len(b)] < d[end][len(b)] {
				end = i
			}
		}
	}
	type pair struct{ i, j int }
	pairs := []pair{}
	i, j := end, len(b)
	for i > 0 || j > 0 {
		if i > 0 && j > 0 {
			cost := 1
			if dictationTokenEqual(a[i-1].text, b[j-1].text) {
				cost = 0
			}
			if d[i][j] == d[i-1][j-1]+cost {
				pairs = append(pairs, pair{i - 1, j - 1})
				i--
				j--
				continue
			}
		}
		if i > 0 && (j == 0 || d[i][j] == d[i-1][j]+1) {
			pairs = append(pairs, pair{i - 1, -1})
			i--
		} else {
			pairs = append(pairs, pair{-1, j - 1})
			j--
		}
	}
	sourceAt, answerAt := 0, 0
	appendSpan := func(kind string, se, ae int) {
		if len(out.Spans) > 0 && out.Spans[len(out.Spans)-1].Kind == kind {
			s := &out.Spans[len(out.Spans)-1]
			s.SourceEnd = se
			s.AnswerEnd = ae
			s.Original = source[s.SourceStart:se]
			s.Written = answer[s.AnswerStart:ae]
		} else {
			out.Spans = append(out.Spans, dictationSpan{ID: fmt.Sprintf("s%d", len(out.Spans)), Kind: kind, SourceStart: sourceAt, SourceEnd: se, AnswerStart: answerAt, AnswerEnd: ae, Original: source[sourceAt:se], Written: answer[answerAt:ae]})
		}
		sourceAt, answerAt = se, ae
	}
	for k := len(pairs) - 1; k >= 0; k-- {
		p := pairs[k]
		kind := "equal"
		se, ae := sourceAt, answerAt
		if p.i >= 0 {
			se = a[p.i].end
			if a[p.i].word {
				out.AttemptedWords++
			}
		}
		if p.j >= 0 {
			ae = b[p.j].end
		}
		switch {
		case p.i < 0:
			kind = "addition"
			if b[p.j].word {
				out.Additions++
			}
		case p.j < 0:
			kind = "omission"
			if a[p.i].word {
				out.Omissions++
			}
		default:
			if norm.NFC.String(a[p.i].text) != norm.NFC.String(b[p.j].text) {
				kind = "substitution"
				if dictationTokenEqual(a[p.i].text, b[p.j].text) {
					kind = "spelling"
				}
				if a[p.i].word {
					out.Substitutions++
				}
			} else if a[p.i].word {
				out.ExactWords++
			}
		}
		if kind != "equal" && ((p.i >= 0 && !a[p.i].word) || (p.j >= 0 && !b[p.j].word)) {
			kind = "punctuation"
		}
		appendSpan(kind, se, ae)
	}
	if end < len(a) {
		out.UnattemptedWords = len(dictationWords.FindAllString(source[sourceAt:], -1))
		kind := "unattempted"
		if out.UnattemptedWords == 0 {
			kind = "punctuation"
		}
		appendSpan(kind, len(source), len(answer))
	}
	if len(out.Spans) == 0 && (len(source) > 0 || len(answer) > 0) {
		appendSpan("unattempted", len(source), len(answer))
	}
	return out
}
