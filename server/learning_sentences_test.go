package main

import (
	"encoding/json"
	"testing"
)

func TestPodcastLibraryCoverageAndPassageFavoritesAreOwnerScoped(t *testing.T) {
	_, h, token, other, j := learningFixture(t)
	// Vocabulary favorites are not passage favorites, even when they cite a segment.
	body := `{"job_id":"` + j.ID + `","segment_id":0,"quote":"lernen gemeinsam","term":"lernen","kind":"word","favorite":true}`
	if w := authCall(h, "POST", "/v1/learning/vocabulary", body, token); w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
	path := "/v1/learning/episodes/" + j.ID + "/passages/0"
	if w := authCall(h, "PUT", path, `{"favorite":true}`, other); w.Code != 404 {
		t.Fatal("foreign mark", w.Code)
	}
	read := func(want int) {
		t.Helper()
		w := authCall(h, "GET", "/v1/podcasts", "", token)
		var out struct {
			Items []struct {
				ID       string `json:"id"`
				Coverage *struct {
					Recognized int `json:"recognized_segments"`
					Translated int `json:"translated_segments"`
					Favorites  int `json:"favorite_passages"`
				} `json:"coverage"`
			} `json:"items"`
		}
		if e := json.Unmarshal(w.Body.Bytes(), &out); e != nil {
			t.Fatal(e)
		}
		if w.Code != 200 || len(out.Items) != 1 || out.Items[0].Coverage == nil {
			t.Fatalf("missing coverage: %d %s", w.Code, w.Body.String())
		}
		c := out.Items[0].Coverage
		if c.Recognized != 1 || c.Translated != 1 || c.Favorites != want {
			t.Fatalf("wrong real counts: %+v", c)
		}
	}
	read(0)
	for i := 0; i < 2; i++ {
		if w := authCall(h, "PUT", path, `{"favorite":true}`, token); w.Code != 200 {
			t.Fatalf("mark %d %s", w.Code, w.Body.String())
		}
	}
	read(1)
	if w := authCall(h, "PUT", path, `{"favorite":false}`, token); w.Code != 200 {
		t.Fatal(w.Code)
	}
	read(0)
	for _, bad := range []string{"-1", "01", "99", "word"} {
		if w := authCall(h, "PUT", "/v1/learning/episodes/"+j.ID+"/passages/"+bad, `{"favorite":true}`, token); w.Code != 400 {
			t.Fatalf("invalid segment %s: %d", bad, w.Code)
		}
	}
}
