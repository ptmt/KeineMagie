package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestTranslationIdempotencyLostAckAndConflict(t *testing.T) {
	t.Setenv("PROVIDER_KEY_FILE", t.TempDir()+"/key")
	if err := os.WriteFile(os.Getenv("PROVIDER_KEY_FILE"), []byte(strings.Repeat("k", 32)), 0600); err != nil {
		t.Fatal(err)
	}
	calls := 0
	terminal := "response.completed"
	var holdCatalog atomic.Bool
	catalogEntered := make(chan struct{}, 1)
	catalogRelease := make(chan struct{})
	cfg := &serverConfig{authPath: t.TempDir() + "/auth.json", historyPath: t.TempDir() + "/history.json", httpClient: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		body := `{"models":[{"slug":"synthetic","display_name":"Synthetic","visibility":"list"}]}`
		if strings.HasSuffix(r.URL.Path, "/models") && holdCatalog.CompareAndSwap(true, false) {
			catalogEntered <- struct{}{}
			<-catalogRelease
		}
		if strings.HasSuffix(r.URL.Path, "/responses") {
			calls++
			body = accountTranslationSSE(`{"text":"Привет"}`, true, terminal)
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(body)), Header: http.Header{}}, nil
	})}}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	token, session, err := cfg.auth.store.create("alice", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if err = cfg.provider.save(session.UserID, providerCredential{ClientID: "oaiapp_test", Subject: "synthetic", AccessToken: "synthetic", RefreshToken: "synthetic", Scope: providerScope, Expires: time.Now().Add(time.Hour)}); err != nil {
		t.Fatal(err)
	}
	key := "b3b07bb8-4f96-4b93-a1ad-0bcb96f4d843"
	call := func(text, owner string) *httptest.ResponseRecorder {
		b, _ := json.Marshal(translationInput{Text: text, SourceLanguage: "de", TargetLanguage: "ru"})
		r := httptest.NewRequest("POST", "/v1/translations", strings.NewReader(string(b)))
		r.Header.Set("Authorization", "Bearer "+token)
		r.Header.Set("Idempotency-Key", key)
		r.Header.Set("X-Translation-Owner", owner)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	exact := "  Hallo e\u0301 👩🏽‍💻\n"
	first := call(exact, session.UserID)
	second := call(exact, session.UserID)
	if first.Code != 201 || second.Code != 201 || first.Body.String() != second.Body.String() || calls != 1 {
		t.Fatalf("lost ack: codes %d/%d provider calls %d", first.Code, second.Code, calls)
	}
	var record translationRecord
	json.Unmarshal(second.Body.Bytes(), &record)
	if record.Text != exact {
		t.Fatal("source text changed")
	}
	if w := call("different", session.UserID); w.Code != 409 || calls != 1 {
		t.Fatalf("conflict %d calls %d", w.Code, calls)
	}
	if w := call(exact, "other-owner"); w.Code != 403 || calls != 1 {
		t.Fatalf("owner mismatch %d", w.Code)
	}
	history := authCall(h, "GET", "/v1/translations", "", token)
	var list struct {
		Items []translationRecord `json:"items"`
	}
	json.Unmarshal(history.Body.Bytes(), &list)
	if len(list.Items) != 1 {
		t.Fatalf("history count %d", len(list.Items))
	}
	// Crash after history commit but before receipt completion must reconcile.
	receiptPath := filepath.Join(cfg.provider.dir, "translation-receipts", sessionHash(session.UserID), sessionHash(key)+".json")
	if err := learningAtomicJSON(receiptPath, translationReceipt{Digest: learningDigest(translationInput{Text: exact, SourceLanguage: "de", TargetLanguage: "ru"})}); err != nil {
		t.Fatal(err)
	}
	if w := call(exact, session.UserID); w.Code != 201 || calls != 1 {
		t.Fatalf("history/receipt recovery %d calls %d", w.Code, calls)
	}
	if err := os.Remove(receiptPath); err != nil {
		t.Fatal(err)
	}
	if w := call("conflicting after receipt loss", session.UserID); w.Code != 409 || calls != 1 {
		t.Fatalf("lost receipt conflict %d calls %d", w.Code, calls)
	}
	// Fresh handler simulates server restart without deleting the receipt.
	h, err = newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if w := call(exact, session.UserID); w.Code != 201 || calls != 1 {
		t.Fatalf("restart %d calls %d", w.Code, calls)
	}
	quotaData, err := os.ReadFile(filepath.Join(cfg.provider.dir, "quotas", sessionHash(session.UserID)+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var quota dailyTranslationQuota
	if json.Unmarshal(quotaData, &quota) != nil || quota.Attempts != 1 {
		t.Fatalf("quota duplicate: %s", quotaData)
	}
	key = "uncertain-request-00001"
	terminal = "response.incomplete"
	if w := call(exact, session.UserID); w.Code != 502 {
		t.Fatalf("incomplete %d", w.Code)
	}
	terminal = "response.completed"
	if w := call(exact, session.UserID); w.Code != 409 || calls != 2 {
		t.Fatalf("ambiguous retry spent: %d calls %d", w.Code, calls)
	}
	// Simulate a crash after durable claim but before provider admission.
	key = "crashed-request-000001"
	path := filepath.Join(cfg.provider.dir, "translation-receipts", sessionHash(session.UserID), sessionHash(key)+".json")
	in := translationInput{Text: exact, SourceLanguage: "de", TargetLanguage: "ru"}
	if err := learningAtomicJSON(path, translationReceipt{Digest: learningDigest(in)}); err != nil {
		t.Fatal(err)
	}
	if w := call(exact, session.UserID); w.Code != 409 || calls != 2 {
		t.Fatalf("crash blindly retried %d calls %d", w.Code, calls)
	}
	key = "status-is-advisory-00001"
	holdCatalog.Store(true)
	statusDone := make(chan struct{})
	go func() { authCall(h, "GET", "/v1/provider", "", token); close(statusDone) }()
	<-catalogEntered
	translated := make(chan *httptest.ResponseRecorder, 1)
	go func() { translated <- call(exact, session.UserID) }()
	select {
	case w := <-translated:
		if w.Code != 201 {
			t.Errorf("status blocked request: %d", w.Code)
		}
	case <-time.After(time.Second):
		t.Error("advisory catalog holds translation owner lock")
	}
	close(catalogRelease)
	<-statusDone
	key = "b3b07bb8-4f96-4b93-a1ad-0bcb96f4d843"
	if w := authCall(h, "DELETE", "/v1/history/"+record.ID, "", token); w.Code != 204 {
		t.Fatalf("delete %d", w.Code)
	}
	if w := call(exact, session.UserID); w.Code != 409 {
		t.Fatalf("deleted history replay %d", w.Code)
	}
}
