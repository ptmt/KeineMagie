package main

import (
	"fmt"
	"golang.org/x/text/unicode/norm"
	"regexp"
	"strings"
)

type dictationDifference struct {
	Kind     string `json:"kind"`
	Original string `json:"original"`
	Written  string `json:"written"`
}

var dictationWords = regexp.MustCompile(`[\p{L}\p{M}\p{N}]+(?:['’][\p{L}\p{M}\p{N}]+)*`)

func dictationGrade(original, written string) []dictationDifference {
	a := dictationWords.FindAllString(norm.NFC.String(original), -1)
	b := dictationWords.FindAllString(norm.NFC.String(written), -1)
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
			if strings.EqualFold(a[i-1], b[j-1]) {
				cost = 0
			}
			d[i][j] = min(d[i-1][j]+1, d[i][j-1]+1, d[i-1][j-1]+cost)
		}
	}
	out := []dictationDifference{}
	i, j := len(a), len(b)
	for i > 0 || j > 0 {
		if i > 0 && j > 0 {
			cost := 1
			if strings.EqualFold(a[i-1], b[j-1]) {
				cost = 0
			}
			if d[i][j] == d[i-1][j-1]+cost {
				kind := "substitution"
				if cost == 0 {
					kind = "case"
				}
				if a[i-1] != b[j-1] {
					out = append(out, dictationDifference{kind, a[i-1], b[j-1]})
				}
				i--
				j--
				continue
			}
		}
		if i > 0 && (j == 0 || d[i][j] == d[i-1][j]+1) {
			out = append(out, dictationDifference{"missing", a[i-1], ""})
			i--
		} else {
			out = append(out, dictationDifference{"extra", "", b[j-1]})
			j--
		}
	}
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	punctuation := func(s string) string {
		s = norm.NFC.String(s)
		positions := dictationWords.FindAllStringIndex(s, -1)
		parts := []string{}
		start := 0
		for index, p := range positions {
			mark := strings.Join(strings.Fields(s[start:p[0]]), "")
			if mark != "" {
				parts = append(parts, fmt.Sprintf("after word %d: %s", index, mark))
			}
			start = p[1]
		}
		if mark := strings.Join(strings.Fields(s[start:]), ""); mark != "" {
			parts = append(parts, fmt.Sprintf("after word %d: %s", len(positions), mark))
		}
		return strings.Join(parts, "; ")
	}
	if punctuation(original) != punctuation(written) {
		out = append(out, dictationDifference{"punctuation", punctuation(original), punctuation(written)})
	}
	return out
}
