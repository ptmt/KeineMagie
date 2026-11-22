package main

import "testing"

func TestPodcastExercisesRequireMeaningfulInterfaceClue(t *testing.T) {
	sources := []coachSource{{ID: "passage-group:episode:0:group", Text: "Ich muss das Paket abholen.", Language: "de", AnswerLanguage: "ru"}}
	for _, kind := range []string{"cloze", "context_translation"} {
		r := coachResult{Kind: kind, SourceID: sources[0].ID, Target: "vocabulary.word_choice"}
		if err := validateCoachClue(r, sources, "en"); err == nil {
			t.Errorf("%s admitted without meaning clue", kind)
		}
		r.Clue = "Collecting a parcel from the delivery office."
		r.ClueKind = "gloss"
		r.ClueLanguage = "en"
		if err := validateCoachClue(r, sources, "en"); err != nil {
			t.Errorf("%s grounded UI clue rejected: %v", kind, err)
		}
		r.Clue = "A suitable verb."
		if err := validateCoachClue(r, sources, "en"); err == nil {
			t.Errorf("%s grammatical category accepted as meaning", kind)
		}
		r.Clue = "Collecting a parcel."
		r.ClueKind = "context"
		r.ClueLanguage = "de"
		if err := validateCoachClue(r, sources, "en"); err == nil {
			t.Errorf("%s clue ignored interface language", kind)
		}
	}
}
