package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
)

func TestPodcastBatchTerminalSnapshots(t *testing.T) {
	valid := `{"segments":[{"id":4,"text":"Привет"}]}`
	for _, snapshot := range []string{
		`{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"different"}]}]}`,
		`{"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"No"}]}]}`,
		`{"status":"incomplete"}`,
		`{"status":"completed","output":[]}`,
	} {
		wire := accountTranslationSSE(valid, true, "") + "data: {\"type\":\"response.completed\",\"response\":" + snapshot + "}\n\n"
		if _, err := readPodcastTranslationSSE(strings.NewReader(wire)); err == nil {
			t.Fatal("invalid terminal snapshot accepted", snapshot)
		}
	}
	if _, err := readPodcastTranslationSSE(strings.NewReader("data: " + strings.Repeat("x", (1<<20)+1))); err == nil {
		t.Fatal("oversized event accepted")
	}
}

func TestPodcastBatchStrictWireMapping(t *testing.T) {
	for _, tc := range []struct {
		name, output, terminal string
		valid                  bool
	}{
		{"string ID", `{"segments":[{"id":"4","text":"Привет"},{"id":8,"text":"Мир"}]}`, "response.completed", false},
		{"reordered", `{"segments":[{"id":8,"text":"Мир"},{"id":4,"text":"Привет"}]}`, "response.completed", true},
		{"missing", `{"segments":[{"id":4,"text":"Привет"}]}`, "response.completed", false},
		{"duplicate", `{"segments":[{"id":4,"text":"Привет"},{"id":4,"text":"Мир"}]}`, "response.completed", false},
		{"renamed", `{"segments":[{"id":4,"text":"Привет"},{"id":9,"text":"Мир"}]}`, "response.completed", false},
		{"extra field", `{"segments":[{"id":4,"text":"Привет","extra":1},{"id":8,"text":"Мир"}]}`, "response.completed", false},
		{"duplicate field", `{"segments":[{"id":4,"id":8,"text":"Привет"},{"id":8,"text":"Мир"}]}`, "response.completed", false},
		{"wrong casing", `{"Segments":[{"id":4,"text":"Привет"},{"id":8,"text":"Мир"}]}`, "response.completed", false},
		{"null", `{"segments":[{"id":4,"text":null},{"id":8,"text":"Мир"}]}`, "response.completed", false},
		{"incomplete", `{"segments":[{"id":4,"text":"Привет"},{"id":8,"text":"Мир"}]}`, "response.incomplete", false},
		{"eof", `{"segments":[{"id":4,"text":"Привет"},{"id":8,"text":"Мир"}]}`, "", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			p := &providerService{client: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
				var body map[string]any
				if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
					t.Fatal(err)
				}
				if body["stream"] != true || body["store"] != false || !strings.Contains(stringMustJSON(body["text"]), `"strict":true`) {
					t.Fatal("missing strict request schema")
				}
				return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(accountTranslationSSE(tc.output, true, tc.terminal))), Header: http.Header{}}, nil
			})}}
			got, err := p.translatePodcastBatch(context.Background(), "synthetic", "offered", "de", "ru", []podcastTranslationItem{{ID: 4, Text: "Hallo"}, {ID: 8, Text: "Welt"}})
			if tc.valid {
				if err != nil || got[4] != "Привет" || got[8] != "Мир" {
					t.Fatalf("%+v %v", got, err)
				}
			} else if err == nil {
				t.Fatal("invalid mapping accepted")
			}
		})
	}
}
func stringMustJSON(value any) string { b, _ := json.Marshal(value); return string(b) }

func TestPodcastTranslationBatchBounds(t *testing.T) {
	segments := make([]podcastSegment, 3600)
	for i := range segments {
		segments[i] = podcastSegment{Start: float64(i * 3), End: float64(i*3 + 2), Text: strings.Repeat("a", 60)}
	}
	segments[0].Translation = "saved"
	batches, err := podcastTranslationBatches(segments)
	if err != nil || len(batches) > 100 {
		t.Fatalf("long episode batches: %d %v", len(batches), err)
	}
	seen := map[int]bool{}
	for _, batch := range batches {
		if len(batch) > 64 {
			t.Fatal("unbounded batch")
		}
		for _, item := range batch {
			if item.ID == 0 || seen[item.ID] {
				t.Fatal("duplicate or completed segment")
			}
			seen[item.ID] = true
		}
	}
	if len(seen) != 3599 {
		t.Fatal("lost segments", len(seen))
	}
}
