package main

import (
	"net/http/httptest"
	"os"
	"regexp"
	"strings"
	"testing"
)

// Exercise the served module graph, not merely the root allowlist string.
func TestDictationServedModuleGraph(t *testing.T) {
	h := authHandler(t)
	docker, err := os.ReadFile("Dockerfile")
	if err != nil {
		t.Fatal(err)
	}
	imports := regexp.MustCompile(`(?:from\s*|import\s*\()\s*['"]\./([^'"]+\.mjs)['"]`)
	queue := []string{"dictation.mjs", "dictation.css"}
	seen := map[string]bool{}
	for len(queue) > 0 {
		name := queue[0]
		queue = queue[1:]
		if seen[name] {
			continue
		}
		seen[name] = true
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", "/"+name, nil))
		if w.Code != 200 || w.Body.Len() == 0 {
			t.Fatalf("%s: %d", name, w.Code)
		}
		if !strings.Contains(string(docker), "web/"+name+" ") {
			t.Fatalf("not packaged: %s", name)
		}
		if strings.HasSuffix(name, ".mjs") && !strings.Contains(w.Header().Get("Content-Type"), "javascript") {
			t.Fatalf("incorrect MIME: %s", name)
		}
		for _, match := range imports.FindAllStringSubmatch(w.Body.String(), -1) {
			queue = append(queue, match[1])
		}
	}
	if !seen["dictation-playback.mjs"] || !seen["dictation-cache.mjs"] {
		t.Fatal("incomplete module graph", seen)
	}
}
