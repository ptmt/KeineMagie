package main

import (
	"strings"
	"unicode"
)

// Applied only at generation admission. Existing saved turns are never rewritten,
// regenerated, or rejected on reads/checks. Semantic clue quality remains a model
// contract; these deterministic checks reject missing/category-only/leaking data.
func validateCoachClue(result coachResult, sources []coachSource, locale string) error {
	vocabulary := result.Kind == "cloze" && strings.HasPrefix(result.Target, "vocabulary.")
	podcastClue := strings.HasPrefix(result.SourceID, "passage-group:") && (result.Kind == "cloze" || result.Kind == "context_translation")
	if !vocabulary && !podcastClue {
		if result.Clue != "" || result.ClueKind != "" || result.ClueLanguage != "" {
			return errCoachResult
		}
		return nil
	}
	clue := strings.TrimSpace(result.Clue)
	if clue == "" || runeCount(clue) > 300 || runeCount(result.ClueLanguage) > 20 {
		return errCoachResult
	}
	tokens := strings.FieldsFunc(strings.ToLower(clue), func(r rune) bool { return !unicode.IsLetter(r) })
	if len(tokens) == 0 {
		return errCoachResult
	}
	generic := strings.Fields("a an the suitable appropriate missing fill in word noun verb adjective adverb preposition article category use insert ein eine einen der die das passendes passende passenden substantiv nomen wort verb adjektiv ergänze geeignetes существительное подходящее слово глагол прилагательное вставьте пропущенное un une le la nom mot approprié appropriée verbe adjectif complète un una el sustantivo adecuado adecuada palabra verbo adjetivo completa")
	meaningful := false
	for _, token := range tokens {
		found := false
		for _, g := range generic {
			if token == g {
				found = true
				break
			}
		}
		if !found {
			meaningful = true
		}
	}
	if !meaningful {
		return errCoachResult
	}
	base := func(language string) string { return strings.ToLower(strings.Split(language, "-")[0]) }
	if podcastClue && (result.ClueKind != "gloss" || base(result.ClueLanguage) != base(locale)) {
		return errCoachResult
	}
	for _, source := range sources {
		if source.ID != result.SourceID {
			continue
		}
		switch result.ClueKind {
		case "gloss":
			if base(result.ClueLanguage) != base(locale) || locale == "" {
				return errCoachResult
			}
		case "synonym", "context":
			if base(result.ClueLanguage) != base(source.Language) || source.Language == "" {
				return errCoachResult
			}
		default:
			return errCoachResult
		}
		return nil
	}
	return errCoachResult
}
