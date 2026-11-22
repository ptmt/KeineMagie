package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestCoachClueFieldGroupsAreAtomic(t *testing.T) {
	input := strings.Replace(vocabularyFixture, `,"target_text":"abholen","answer_language":"en"`, `,"clue":"some meaning","clue_language":"en"`, 1)
	input = strings.Replace(input, `"kind":"context_translation"`, `"kind":"cloze"`, 1)
	if _, err := decodeCoach(input, vocabularySources(t)); err == nil {
		t.Fatal("partial additive group accepted")
	}
}

func TestCoachVocabularyClueContract(t *testing.T) {
	source := []coachSource{{ID: "translation:original", Language: "de", Text: "Ich mache ein Praktikum bei euch."}}
	base := map[string]any{"message": "Complete the sentence.", "kind": "cloze", "prompt": "Ich mache ein ___ bei euch.", "target": "vocabulary.word_choice", "source_id": "translation:original", "quote": source[0].Text, "answers": []string{"Praktikum"}, "incorrect_answers": []string{}, "explanation": "An internship.", "target_text": "", "answer_language": ""}
	decode := func(m map[string]any) coachResult {
		b, _ := json.Marshal(m)
		r, e := decodeCoach(string(b), source)
		if e != nil {
			t.Fatal(e, string(b))
		}
		return r
	}
	legacy := decode(base)
	if validateCoachClue(legacy, source, "en") == nil {
		t.Fatal("new vocabulary generation accepted an underdetermined category-only task")
	}
	for locale, clue := range map[string]string{"en": "a period of practical work experience", "de": "eine zeitlich begrenzte praktische Berufserfahrung", "ru": "период практического знакомства с профессией", "fr": "une période de formation pratique en entreprise", "es": "un periodo de formación práctica en una empresa"} {
		m := map[string]any{}
		for k, v := range base {
			m[k] = v
		}
		m["clue"] = clue
		m["clue_kind"] = "gloss"
		m["clue_language"] = locale
		r := decode(m)
		if e := validateCoachClue(r, source, locale); e != nil {
			t.Fatal(locale, e)
		}
		wire, _ := json.Marshal(coachView(&coachData{Turns: []coachTurn{{ID: "clue", Result: &r, State: "completed"}}}))
		if !strings.Contains(string(wire), `"clue":`) || strings.Contains(string(wire), "Praktikum") {
			t.Fatal("clue lost or answer leaked", string(wire))
		}
		var public struct {
			Turns []struct {
				Message string `json:"message"`
			} `json:"turns"`
		}
		json.Unmarshal(wire, &public)
		if !strings.Contains(public.Turns[0].Message, clue) {
			t.Fatal("older clients cannot see the meaning clue")
		}
		if locale != "en" && validateCoachClue(r, source, "en") == nil {
			t.Fatal("wrong UI language accepted")
		}
	}
	for _, clue := range []string{"noun", "a suitable noun", "существительное", "passendes Substantiv", "nom approprié", "sustantivo adecuado"} {
		m := map[string]any{}
		for k, v := range base {
			m[k] = v
		}
		m["clue"] = clue
		m["clue_kind"] = "gloss"
		m["clue_language"] = "en"
		b, _ := json.Marshal(m)
		r, e := decodeCoach(string(b), source)
		if e == nil && validateCoachClue(r, source, "en") == nil {
			t.Fatal("grammar category is not a meaning clue", clue)
		}
	}
	m := map[string]any{}
	for k, v := range base {
		m[k] = v
	}
	m["clue"] = "Praktikum"
	m["clue_kind"] = "synonym"
	m["clue_language"] = "de"
	b, _ := json.Marshal(m)
	if _, e := decodeCoach(string(b), source); e == nil {
		t.Fatal("expected answer leaked via clue")
	}
}
