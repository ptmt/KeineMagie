package main

import (
	"strings"
	"unicode"
)

type dictationSegment struct {
	Kind  string `json:"kind"`
	Text  string `json:"text,omitempty"`
	Asset int    `json:"asset"`
}

// Conservative German sentence boundaries. Original storage is never normalized.
func dictationSentences(text string) []string {
	r := []rune(text)
	start := 0
	out := []string{}
	abbreviations := []string{"dr.", "prof.", "bzw.", "z.", "b.", "d.", "h.", "u.", "a.", "ca.", "nr.", "usw.", "etc."}
	for i, c := range r {
		if c != '.' && c != '!' && c != '?' {
			continue
		}
		if c == '.' {
			if i > 0 && i+1 < len(r) && unicode.IsDigit(r[i-1]) && unicode.IsDigit(r[i+1]) {
				continue
			}
			prefix := strings.ToLower(string(r[start : i+1]))
			abbr := false
			for _, a := range abbreviations {
				if strings.HasSuffix(prefix, a) {
					before := len(prefix) - len(a)
					if before == 0 || prefix[before-1] == ' ' {
						abbr = true
						break
					}
				}
			}
			if abbr {
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
func dictationChunks(sentence string) []string {
	words := strings.Fields(sentence)
	if len(words) <= 14 {
		return nil
	}
	out := []string{}
	for len(words) > 0 {
		n := min(12, len(words))
		if len(words) > 12 {
			for i := n - 1; i >= 4; i-- {
				if strings.ContainsAny(words[i], ",;:—") {
					n = i + 1
					break
				}
			}
		}
		out = append(out, strings.Join(words[:n], " "))
		words = words[n:]
	}
	return out
}
func dictationPlan(text string) []dictationSegment {
	out := []dictationSegment{{Kind: "whole", Text: text, Asset: 0}}
	assets := map[string]int{text: 0}
	add := func(kind, text string) {
		id, ok := assets[text]
		if !ok {
			id = len(assets)
			assets[text] = id
		}
		out = append(out, dictationSegment{kind, text, id})
	}
	for _, s := range dictationSentences(text) {
		add("sentence", s)
		for _, c := range dictationChunks(s) {
			add("chunk", c)
		}
		add("sentence_repeat", s)
	}
	add("final", text)
	return out
}
