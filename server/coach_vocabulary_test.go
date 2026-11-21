package main

import (
	"encoding/json"
	"strings"
	"testing"
)

const vocabularyFixture = `{"message":"Translate only the highlighted expression into English.","kind":"context_translation","prompt":"Ich muss das Paket abholen.","target":"vocabulary.word_choice","source_id":"translation:original","quote":"Ich muss das Paket abholen.","answers":["pick up"],"incorrect_answers":[],"explanation":"Here abholen means collecting something.","target_text":"abholen","answer_language":"en"}`

func vocabularySources(t *testing.T) []coachSource {
	t.Helper()
	var sources []coachSource
	if err := json.Unmarshal([]byte(`[{"id":"translation:original","text":"Ich muss das Paket abholen.","language":"de","answer_language":"en"}]`), &sources); err != nil {
		t.Fatal(err)
	}
	return sources
}

func TestCoachAdditiveFieldsDoNotRelaxRequiredLegacyArrays(t *testing.T) {
	input := `{"message":"Explanation","kind":"clarification","prompt":"","target":"vocabulary.word_choice","source_id":"translation:original","quote":"Ich muss das Paket abholen.","explanation":"Context","target_text":"","answer_language":""}`
	if _, err := decodeCoach(input, vocabularySources(t)); err == nil {
		t.Fatal("missing answer arrays accepted")
	}
}

func TestCoachContextTranslationUsesEachSavedPairDirection(t *testing.T) {
	input := `{"message":"Translate collect into German.","kind":"context_translation","prompt":"I need to collect the parcel.","target":"vocabulary.word_choice","source_id":"translation:reverse","quote":"I need to collect the parcel.","answers":["abholen"],"incorrect_answers":[],"explanation":"Collect refers to picking up the parcel.","target_text":"collect","answer_language":"de"}`
	source := coachSource{ID: "translation:reverse", Text: "I need to collect the parcel.", Language: "en", AnswerLanguage: "de"}
	if _, err := decodeCoach(input, []coachSource{source}); err != nil {
		t.Fatal("explicit opposite saved direction rejected", err)
	}
	source.AnswerLanguage = ""
	if _, err := decodeCoach(input, []coachSource{source}); err == nil {
		t.Fatal("missing course direction inferred")
	}
}

func TestCoachContextTranslationGroundedContract(t *testing.T) {
	sources := vocabularySources(t)
	result, err := decodeCoach(vocabularyFixture, sources)
	if err != nil {
		t.Fatal("grounded contextual translation rejected", err)
	}
	b, _ := json.Marshal(result)
	if !strings.Contains(string(b), `"target_text":"abholen"`) {
		t.Fatal("lost target", string(b))
	}
	view := coachView(&coachData{Turns: []coachTurn{{ID: "word", State: "completed", Language: "de", Result: &result}}})
	public, _ := json.Marshal(view)
	if !strings.Contains(string(public), `"answer_language":"en"`) || !strings.Contains(string(public), `"target_text"`) {
		t.Fatal("missing public target direction", string(public))
	}
	if strings.Contains(string(public), "pick up") {
		t.Fatal("answer leaked before check")
	}
}

func TestCoachContextTranslationRejectsAmbiguousTargetAndDirection(t *testing.T) {
	for name, input := range map[string]string{
		"partial word":          strings.Replace(vocabularyFixture, `"target_text":"abholen"`, `"target_text":"ole"`, 1),
		"missing base fields":   strings.Replace(strings.Replace(vocabularyFixture, `"incorrect_answers":[],`, "", 1), `"target_text":"abholen",`, "", 1),
		"foreign target":        strings.Replace(vocabularyFixture, `"target_text":"abholen"`, `"target_text":"absent"`, 1),
		"wrong direction":       strings.Replace(vocabularyFixture, `"answer_language":"en"`, `"answer_language":"fr"`, 1),
		"changed context":       strings.Replace(vocabularyFixture, `"prompt":"Ich muss das Paket abholen."`, `"prompt":"Ich hole sie ab."`, 1),
		"whole sentence target": strings.Replace(vocabularyFixture, `"target_text":"abholen"`, `"target_text":"Ich muss das Paket abholen."`, 1),
		"missing target":        strings.Replace(vocabularyFixture, `,"target_text":"abholen"`, "", 1),
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := decodeCoach(input, vocabularySources(t)); err == nil {
				t.Fatal("invalid context accepted")
			}
		})
	}
}
