package main

import (
	"encoding/json"
	"net/http"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func historyFixture(t *testing.T) (*serverConfig, http.Handler, string, string, *historyStore) {
	t.Helper()
	dir := t.TempDir()
	cfg := &serverConfig{authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json")}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	token, owner, err := cfg.auth.store.create("owner", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	store, err := openHistory(filepath.Join(dir, "users", sessionHash(owner.UserID)+".json"))
	if err != nil {
		t.Fatal(err)
	}
	if err = store.append(translationRecord{ID: "test-record", CreatedAt: time.Now().UTC(), translationInput: translationInput{Text: "Hallo"}, translationResult: translationResult{Translation: "Привет", Idioms: []idiom{}, Patterns: []pattern{}, Vocabulary: []vocabularyItem{}}}); err != nil {
		t.Fatal(err)
	}
	second, _, err := cfg.auth.store.create("owner", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	return cfg, h, token, second, store
}

func TestHistoryDeletePersistsAcrossClientsAndRestart(t *testing.T) {
	cfg, h, token, second, _ := historyFixture(t)
	w := authCall(h, "DELETE", "/v1/history/test-record", "", token)
	if w.Code != 204 || w.Body.Len() != 0 {
		t.Fatalf("DELETE %d %s", w.Code, w.Body.String())
	}
	restarted, err := newHandler(&serverConfig{authPath: cfg.authPath, historyPath: cfg.historyPath})
	if err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"/v1/history", "/v1/translations"} {
		w = authCall(restarted, "GET", path, "", second)
		if w.Code != 200 || strings.TrimSpace(w.Body.String()) != `{"items":[]}` {
			t.Fatalf("deleted record survived %d %s", w.Code, w.Body.String())
		}
	}
	for _, method := range []string{"DELETE", "PATCH"} {
		w = authCall(restarted, method, "/v1/history/test-record", `{"favorite":true}`, second)
		if w.Code != 404 {
			t.Fatalf("deleted %s %d", method, w.Code)
		}
	}
}

func TestHistoryFavoritePersistsAcrossClientsAndRestart(t *testing.T) {
	cfg, h, token, second, _ := historyFixture(t)
	for _, favorite := range []bool{true, false} {
		body, _ := json.Marshal(map[string]bool{"favorite": favorite})
		w := authCall(h, "PATCH", "/v1/history/test-record", string(body), token)
		if w.Code != 200 {
			t.Fatalf("PATCH %d: %s", w.Code, w.Body.String())
		}
		var record map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &record); err != nil {
			t.Fatal(err)
		}
		if record["id"] != "test-record" || record["text"] != "Hallo" || (record["favorite"] == true) != favorite {
			t.Fatalf("record: %v", record)
		}
		restarted, err := newHandler(&serverConfig{authPath: cfg.authPath, historyPath: cfg.historyPath})
		if err != nil {
			t.Fatal(err)
		}
		for _, path := range []string{"/v1/history", "/v1/translations"} {
			w = authCall(restarted, "GET", path, "", second)
			var list struct {
				Items []struct {
					ID       string `json:"id"`
					Favorite bool   `json:"favorite"`
				} `json:"items"`
			}
			if err := json.Unmarshal(w.Body.Bytes(), &list); err != nil {
				t.Fatal(err)
			}
			if w.Code != 200 || len(list.Items) != 1 || list.Items[0].Favorite != favorite {
				t.Fatalf("reopened %s: %d %s", path, w.Code, w.Body.String())
			}
		}
	}
}
