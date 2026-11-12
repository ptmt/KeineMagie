package main

import (
	"context"
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

func followupFixture(t *testing.T, transport http.RoundTripper) (*serverConfig, http.Handler, string, string, *historyStore) {
	t.Helper()
	t.Setenv("WEB_ORIGIN", "https://example.com")
	key := filepath.Join(t.TempDir(), "key")
	if err := os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PROVIDER_KEY_FILE", key)
	dir := t.TempDir()
	cfg := &serverConfig{authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json"), httpClient: &http.Client{Transport: transport}}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	native, s, err := cfg.auth.store.create("fixture-owner", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	browser, err := cfg.auth.store.createBrowser(native, s.UserID, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if err = cfg.provider.save(s.UserID, providerCredential{AccessToken: "synthetic", Expires: time.Now().Add(time.Hour)}); err != nil {
		t.Fatal(err)
	}
	store, err := openHistory(filepath.Join(dir, "users", sessionHash(s.UserID)+".json"))
	if err != nil {
		t.Fatal(err)
	}
	if err = store.append(translationRecord{ID: "saved", CreatedAt: time.Now(), translationInput: translationInput{Text: "лук", SourceLanguage: "ru", TargetLanguage: "de"}, translationResult: translationResult{Translation: "Zwiebel"}}); err != nil {
		t.Fatal(err)
	}
	return cfg, h, browser, s.UserID, store
}
func followupCall(h http.Handler, token, body string) *httptest.ResponseRecorder {
	r := httptest.NewRequest("POST", "/v1/translation-followups", strings.NewReader(body))
	r.AddCookie(&http.Cookie{Name: browserCookie, Value: token})
	r.Header.Set("Origin", "https://example.com")
	r.Header.Set("X-CSRF-Token", browserCSRF(token))
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

const followupValidBody = `{"history_id":"saved","request_id":"r1","question":"оружие","locale":"ru","expected_turns":0}`

func followupQuotaAttempts(t *testing.T, cfg *serverConfig, owner string) int {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(cfg.provider.dir, "quotas", sessionHash(owner)+".json"))
	if os.IsNotExist(err) {
		return 0
	}
	if err != nil {
		t.Fatal(err)
	}
	var q dailyTranslationQuota
	if json.Unmarshal(data, &q) != nil {
		t.Fatal("invalid quota")
	}
	return q.Attempts
}
func TestFollowupValidationNoCharge(t *testing.T) {
	calls := 0
	cfg, h, browser, owner, store := followupFixture(t, transportFunc(func(*http.Request) (*http.Response, error) { calls++; return nil, io.ErrUnexpectedEOF }))
	cases := []string{
		strings.Replace(followupValidBody, `"оружие"`, `" "`, 1), strings.Replace(followupValidBody, `"оружие"`, `"`+strings.Repeat("😀", 2001)+`"`, 1), strings.Replace(followupValidBody, `"locale":"ru"`, `"locale":"xx"`, 1), strings.Replace(followupValidBody, `"history_id":"saved"`, `"history_id":"../saved"`, 1), strings.Replace(followupValidBody, `"request_id":"r1"`, `"request_id":""`, 1), strings.Replace(followupValidBody, `"expected_turns":0`, `"expected_turns":-1`, 1), strings.TrimSuffix(followupValidBody, "}") + `,"conversation_id":"other"}`, followupValidBody + `{}`,
	}
	for i, body := range cases {
		if w := followupCall(h, browser, body); w.Code != 400 {
			t.Errorf("case %d: %d %s", i, w.Code, w.Body.String())
		}
	}
	if w := followupCall(h, browser, strings.Replace(followupValidBody, "saved", "missing", 1)); w.Code != 404 {
		t.Errorf("missing %d", w.Code)
	}
	_, err := store.followupRecord("saved", func(r *translationRecord) error {
		for i := 0; i < 6; i++ {
			r.Followups = append(r.Followups, translationFollowup{RequestID: string(rune('a' + i)), Question: "question", Answer: "answer"})
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if w := followupCall(h, browser, strings.Replace(followupValidBody, `"expected_turns":0`, `"expected_turns":6`, 1)); w.Code != 409 || !strings.Contains(w.Body.String(), "6 questions") {
		t.Errorf("cap %d %s", w.Code, w.Body.String())
	}
	if calls != 0 || followupQuotaAttempts(t, cfg, owner) != 0 {
		t.Fatal("invalid requests billed")
	}
}
func TestFollowupMissingProviderAndBudgetNoInference(t *testing.T) {
	for _, scenario := range []string{"missing provider", "missing catalog", "empty model", "quota"} {
		t.Run(scenario, func(t *testing.T) {
			calls := 0
			cfg, h, browser, owner, _ := followupFixture(t, transportFunc(func(r *http.Request) (*http.Response, error) {
				calls++
				if scenario == "empty model" {
					return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(`{"models":[]}`))}, nil
				}
				return nil, io.ErrUnexpectedEOF
			}))
			want := 503
			attempts := 0
			switch scenario {
			case "missing provider":
				if err := os.Remove(cfg.provider.credentialPath(owner)); err != nil {
					t.Fatal(err)
				}
			case "missing catalog", "empty model":
				want = 502
			case "quota":
				t.Setenv("TRANSLATION_DAILY_ATTEMPTS", "1")
				release, err := cfg.provider.beginTranslation(owner, time.Now())
				if err != nil {
					t.Fatal(err)
				}
				release()
				want = 429
				attempts = 1
			}
			w := followupCall(h, browser, followupValidBody)
			if w.Code != want {
				t.Fatalf("status %d %s", w.Code, w.Body.String())
			}
			if followupQuotaAttempts(t, cfg, owner) != attempts {
				t.Fatal("unsent request charged")
			}
			if scenario == "quota" && calls != 0 {
				t.Fatal("quota called upstream")
			}
		})
	}
}
func TestFollowupStrictResponseAndCompletion(t *testing.T) {
	for _, tc := range []struct {
		name, output, terminal string
		valid                  bool
	}{
		{"explanation only", `{"answer":"Объяснение","revised_text":null,"revised_source_text":null}`, "response.completed", true},
		{"unicode revision", `{"revised_text":"  Bogen 😀\n ","answer":"Оружие","revised_source_text":null}`, "response.completed", true},
		{"missing revision", `{"answer":"x"}`, "response.completed", false},
		{"null answer", `{"answer":null,"revised_text":null,"revised_source_text":null}`, "response.completed", false},
		{"blank answer", `{"answer":" ","revised_text":null,"revised_source_text":null}`, "response.completed", false},
		{"blank revision", `{"answer":"x","revised_text":" ","revised_source_text":null}`, "response.completed", false},
		{"duplicate", `{"answer":"x","answer":"y","revised_text":null,"revised_source_text":null}`, "response.completed", false},
		{"unknown", `{"answer":"x","revised_text":null,"extra":true,"revised_source_text":null}`, "response.completed", false},
		{"case sensitive", `{"Answer":"x","revised_text":null,"revised_source_text":null}`, "response.completed", false},
		{"two objects", `{"answer":"x","revised_text":null,"revised_source_text":null}{}`, "response.completed", false},
		{"failed", `{"answer":"x","revised_text":null,"revised_source_text":null}`, "response.failed", false},
		{"incomplete", `{"answer":"x","revised_text":null,"revised_source_text":null}`, "response.incomplete", false},
		{"interrupted", `{"answer":"x","revised_text":null,"revised_source_text":null}`, "", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			p := &providerService{client: &http.Client{Transport: transportFunc(func(*http.Request) (*http.Response, error) {
				return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(accountTranslationSSE(tc.output, true, tc.terminal)))}, nil
			})}}
			answer, revision, _, err := p.clarify(context.Background(), "synthetic", "offered", translationRecord{}, followupInput{})
			if tc.valid {
				if err != nil || answer == "" {
					t.Fatalf("valid rejected %v", err)
				}
				if tc.name == "unicode revision" && (revision == nil || *revision != "  Bogen 😀\n ") {
					t.Fatal("revision normalized")
				}
			} else if err == nil {
				t.Fatalf("invalid accepted %q", answer)
			}
		})
	}
}
func TestFollowupFailureChargesSentAttemptWithoutSaving(t *testing.T) {
	cfg, h, browser, owner, store := followupFixture(t, transportFunc(func(r *http.Request) (*http.Response, error) {
		if strings.Contains(r.URL.Path, "models") {
			return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(`{"models":[{"slug":"offered","visibility":"list"}]}`))}, nil
		}
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(accountTranslationSSE(`{"answer":"fake","revised_text":null,"revised_source_text":null}`, true, "response.incomplete")))}, nil
	}))
	w := followupCall(h, browser, followupValidBody)
	if w.Code != 502 || strings.Contains(w.Body.String(), "fake") {
		t.Fatalf("failure leaked %d %s", w.Code, w.Body.String())
	}
	if followupQuotaAttempts(t, cfg, owner) != 1 {
		t.Fatal("sent attempt not charged")
	}
	r, err := store.followupRecord("saved", nil)
	if err != nil || len(r.Followups) != 0 || r.Translation != "Zwiebel" {
		t.Fatal("failure changed original/history")
	}
}
func TestFollowupRevocationIsSerializedWithFinalPersistence(t *testing.T) {
	entered, release := make(chan struct{}), make(chan struct{})
	cfg, h, browser, _, store := followupFixture(t, transportFunc(func(r *http.Request) (*http.Response, error) {
		if strings.Contains(r.URL.Path, "models") {
			return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(`{"models":[{"slug":"offered","visibility":"list"}]}`))}, nil
		}
		close(entered)
		<-release
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(accountTranslationSSE(`{"answer":"private","revised_text":null,"revised_source_text":null}`, true, "response.completed")))}, nil
	}))
	// Hold the history sidecar while completion passes the old standalone auth check.
	locked, unlock := make(chan struct{}), make(chan struct{})
	done := make(chan *httptest.ResponseRecorder, 1)
	go func() { done <- followupCall(h, browser, followupValidBody) }()
	<-entered
	lockDone := make(chan error, 1)
	go func() { lockDone <- store.locked(func() error { close(locked); <-unlock; return nil }) }()
	<-locked
	checked := make(chan struct{})
	var clocks atomic.Int32
	cfg.auth.now = func() time.Time {
		if clocks.Add(1) == 1 {
			close(checked)
		}
		return time.Now()
	}
	close(release)
	<-checked
	// Give the handler time to reach the contended history lock after its auth read.
	time.Sleep(30 * time.Millisecond)
	revoked := make(chan error, 1)
	go func() { revoked <- cfg.auth.store.revoke(browser, time.Now()) }()
	revokedFirst := false
	select {
	case err := <-revoked:
		if err != nil {
			t.Fatal(err)
		}
		revokedFirst = true
	case <-time.After(100 * time.Millisecond):
	}
	close(unlock)
	if err := <-lockDone; err != nil {
		t.Fatal(err)
	}
	response := <-done
	if !revokedFirst {
		if err := <-revoked; err != nil {
			t.Fatal(err)
		}
	}
	record, err := store.followupRecord("saved", nil)
	if err != nil {
		t.Fatal(err)
	}
	if revokedFirst && (len(record.Followups) != 0 || response.Code != 401) {
		t.Fatalf("revocation completed before persistence but result saved: status=%d turns=%d", response.Code, len(record.Followups))
	}
}

func TestFollowupConcurrentHistoryMutation(t *testing.T) {
	for _, operation := range []string{"delete", "favorite"} {
		t.Run(operation, func(t *testing.T) {
			entered, release := make(chan struct{}), make(chan struct{})
			_, h, browser, _, store := followupFixture(t, transportFunc(func(r *http.Request) (*http.Response, error) {
				if strings.Contains(r.URL.Path, "models") {
					return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(`{"models":[{"slug":"offered","visibility":"list"}]}`))}, nil
				}
				close(entered)
				<-release
				return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(accountTranslationSSE(`{"answer":"answer","revised_text":"Bogen","revised_source_text":null}`, true, "response.completed")))}, nil
			}))
			done := make(chan *httptest.ResponseRecorder, 1)
			go func() { done <- followupCall(h, browser, followupValidBody) }()
			<-entered
			if operation == "delete" {
				if err := store.delete("saved"); err != nil {
					t.Fatal(err)
				}
			} else {
				if _, err := store.favorite("saved", true); err != nil {
					t.Fatal(err)
				}
			}
			close(release)
			response := <-done
			record, err := store.followupRecord("saved", nil)
			if operation == "delete" {
				if response.Code != 404 || err != errHistoryNotFound {
					t.Fatalf("deleted parent resurrected: status=%d err=%v", response.Code, err)
				}
			} else if response.Code != 201 || err != nil || !record.Favorite || len(record.Followups) != 1 || record.Translation != "Zwiebel" {
				t.Fatalf("favorite/original lost: status=%d record=%+v err=%v", response.Code, record, err)
			}
		})
	}
}

func TestFollowupConcurrentAdmissionAndRevocation(t *testing.T) {
	entered := make(chan struct{})
	release := make(chan struct{})
	var calls atomic.Int32
	cfg, h, browser, owner, store := followupFixture(t, transportFunc(func(r *http.Request) (*http.Response, error) {
		if strings.Contains(r.URL.Path, "models") {
			return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(`{"models":[{"slug":"offered","visibility":"list"}]}`))}, nil
		}
		calls.Add(1)
		close(entered)
		<-release
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(accountTranslationSSE(`{"answer":"private answer","revised_text":null,"revised_source_text":null}`, true, "response.completed")))}, nil
	}))
	done := make(chan *httptest.ResponseRecorder, 1)
	go func() { done <- followupCall(h, browser, followupValidBody) }()
	<-entered
	if w := followupCall(h, browser, followupValidBody); w.Code != 429 {
		t.Fatalf("duplicate pending %d", w.Code)
	}
	// Revoke while real (synthetic) inference is pending, not merely before admission.
	r := httptest.NewRequest("POST", "/v1/web/logout", strings.NewReader(`{}`))
	r.AddCookie(&http.Cookie{Name: browserCookie, Value: browser})
	r.Header.Set("Origin", "https://example.com")
	r.Header.Set("X-CSRF-Token", browserCSRF(browser))
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 204 {
		t.Fatalf("revoke %d", w.Code)
	}
	close(release)
	w = <-done
	if w.Code != 401 || strings.Contains(w.Body.String(), "private answer") {
		t.Fatalf("revoked response %d %s", w.Code, w.Body.String())
	}
	record, err := store.followupRecord("saved", nil)
	if err != nil || len(record.Followups) != 0 {
		t.Fatal("revoked saved")
	}
	if calls.Load() != 1 || followupQuotaAttempts(t, cfg, owner) != 1 {
		t.Fatal("duplicate inference/charge")
	}
}
