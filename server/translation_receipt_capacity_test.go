package main

import (
	"fmt"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"
)

func TestTranslationReceiptAdmissionBoundAndReplay(t *testing.T) {
	cfg := &serverConfig{provider: &providerService{dir: t.TempDir()}}
	history, err := openHistory(filepath.Join(t.TempDir(), "history.json"))
	if err != nil {
		t.Fatal(err)
	}
	owner := "synthetic"
	dir := filepath.Join(cfg.provider.dir, "translation-receipts", sessionHash(owner))
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	input := translationInput{Text: "private original", SourceLanguage: "de", TargetLanguage: "ru"}
	for i := 0; i < translationReceiptLimit-1; i++ {
		if err := learningAtomicJSON(filepath.Join(dir, fmt.Sprintf("filler-%d.json", i)), translationReceipt{Digest: "spent"}); err != nil {
			t.Fatal(err)
		}
	}
	type outcome struct {
		claim *translationClaim
		code  int
	}
	results := make(chan outcome, 2)
	var wg sync.WaitGroup
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			r := httptest.NewRequest("POST", "/", nil)
			r.Header.Set("Idempotency-Key", fmt.Sprintf("synthetic-capacity-%d", i))
			w := httptest.NewRecorder()
			c, _ := cfg.claimTranslation(w, r, owner, input, history)
			results <- outcome{c, w.Code}
		}(i)
	}
	wg.Wait()
	close(results)
	var accepted *translationClaim
	rejected := 0
	for result := range results {
		if result.claim != nil {
			if accepted != nil {
				t.Fatal("concurrent limit exceeded")
			}
			accepted = result.claim
		} else if result.code == 429 {
			rejected++
		} else {
			t.Fatalf("unexpected status %d", result.code)
		}
	}
	if accepted == nil || rejected != 1 {
		t.Fatal("admission must accept exactly one")
	}
	record := translationRecord{ID: accepted.recordID, translationInput: input, translationResult: translationResult{Translation: "private result"}}
	if err := history.appendOnce(record); err != nil {
		t.Fatal(err)
	}
	if err := accepted.complete(record); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != translationReceiptLimit+1 {
		t.Fatalf("rejected keys grew sidecars: %d", len(entries))
	}
	for i := 0; i < 2; i++ {
		r := httptest.NewRequest("POST", "/", nil)
		r.Header.Set("Idempotency-Key", fmt.Sprintf("synthetic-capacity-%d", i))
		w := httptest.NewRecorder()
		cfg.claimTranslation(w, r, owner, input, history)
		if w.Code != 201 && w.Code != 429 {
			t.Fatalf("full capacity replay %d", w.Code)
		}
	}
	if err := history.delete(record.ID); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(accepted.path)
	if err != nil {
		t.Fatal(err)
	}
	if string(b) == "" {
		t.Fatal("spent tombstone lost")
	}
}
