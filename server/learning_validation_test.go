package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestLearningStrictSchemaAndRecommendationGrounding(t *testing.T) {
	j := podcastJob{SourceLanguage: "de", Segments: []podcastSegment{{Text: "Wir drücken die Daumen.", Start: 3, End: 8}}}
	p := learningProfile{CEFR: "B1"}
	allowed := map[int]bool{0: true}
	valid := `{"narrative":[{"text":"Hoffnung.","citations":[{"segment_id":0,"quote":"drücken die Daumen"}]}],"topics":[{"title":"Hoffnung","key_points":[{"text":"Wünsche.","citations":[{"segment_id":0,"quote":"Daumen"}]}]}],"recommendations":[{"kind":"idiom","term":"drücken die Daumen","translation":"держать кулаки","reason":"Useful expression of hope for B1.","cefr":"B1","citation":{"segment_id":0,"quote":"drücken die Daumen"}}]}`
	result, e := learningDecodeResult(valid, j, allowed, p, nil)
	if e != nil || result.Recommendations[0].Citation.Start != 3 {
		t.Fatal(e, result)
	}
	for _, bad := range []string{valid + ` !`,
		valid[:len(valid)-1] + `},`, valid + ` {}`, strings.Replace(valid, `"segment_id":0`, `"segment_id":0,"segment_id":0`, 1), strings.Replace(valid, `"narrative"`, `"Narrative"`, 1), strings.Replace(valid, `"quote":"Daumen"`, `"quote":"made up"`, 1), strings.Replace(valid, `"term":"drücken die Daumen"`, `"term":"invented"`, 1), strings.Replace(valid, `"cefr":"B1"`, `"cefr":"D1"`, 1), strings.Replace(valid, `"quote":"Daumen"`, `"quote":"Daumen","start":42`, 1)} {
		if _, e = learningDecodeResult(bad, j, allowed, p, nil); e == nil {
			t.Errorf("accepted invalid %s", bad)
		}
	}
	if _, e = learningDecodeResult(valid, j, allowed, learningProfile{CEFR: "unknown"}, nil); e == nil {
		t.Fatal("recommendation without assessment")
	}
	if _, e = learningDecodeResult(valid, j, allowed, p, []learningVocabulary{{Language: "de", Term: "drücken die Daumen", Status: "known"}}); e == nil {
		t.Fatal("recommended known term")
	}
}
func TestLearningCacheTracksTranscriptAndActualProgress(t *testing.T) {
	_, h, token, _, j := learningFixture(t)
	path := "/v1/learning/episodes/" + j.ID + "/analysis"
	w := authCall(h, "GET", path, "", token)
	var initial learningAnalysisView
	json.Unmarshal(w.Body.Bytes(), &initial)
	authCall(h, "PUT", "/v1/learning/profiles/de", `{"cefr":"A1"}`, token)
	w = authCall(h, "GET", path, "", token)
	var updated learningAnalysisView
	json.Unmarshal(w.Body.Bytes(), &updated)
	if updated.CEFR != "A1" || updated.ProfileRequired {
		t.Fatal("level not reflected")
	}
	if initial.TranscriptHash != updated.TranscriptHash {
		t.Fatal("profile changed transcript hash")
	}
}
