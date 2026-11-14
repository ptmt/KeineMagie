package main

import (
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"
)

func TestCoachFailureStageAndSafeReference(t *testing.T) {
	for code, phase := range map[string]string{"catalog_unavailable": "catalog", "model_unavailable": "catalog", "connection_required": "provider_auth", "storage": "storage", "sources_required": "sources", "sources_unavailable": "sources", "session": "session", "invalid": "request", "quota": "admission", "conflict": "storage", "canceled": "canceled"} {
		w := httptest.NewRecorder()
		coachFailure(w, 503, code, "synthetic")
		if w.Header().Get("X-Coach-Phase") != phase {
			t.Fatalf("wrong phase for %s", code)
		}
	}
	w := httptest.NewRecorder()
	cfg := &serverConfig{}
	cfg.coachHTTP(w, httptest.NewRequest("DELETE", "/v1/learning/coach", nil), "synthetic")
	if !regexp.MustCompile(`^[a-f0-9]{32}$`).MatchString(w.Header().Get("X-Coach-Request-ID")) {
		t.Fatal("missing safe request reference")
	}
	if w.Code != 405 || !strings.Contains(w.Body.String(), `"code":"coach_invalid"`) {
		t.Fatal("code/status lost")
	}
}

// Capture actual handler stdout/stderr in an isolated test process, not a global
// stdout swap that could race unrelated tests. All credentials/content are fake.
func TestCoachDiagnosticsPrivacy(t *testing.T) {
	if os.Getenv("KM_COACH_DIAGNOSTIC_CHILD") != "1" {
		cmd := exec.Command(os.Args[0], "-test.run=^TestCoachDiagnosticsPrivacy$", "-test.count=1")
		cmd.Env = append(os.Environ(), "KM_COACH_DIAGNOSTIC_CHILD=1")
		output, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("synthetic diagnostics child failed: %s", output)
		}
		text := string(output)
		if strings.Contains(text, "PRIVATE_SENTINEL") {
			t.Fatal("private synthetic data escaped into logs")
		}
		request := regexp.MustCompile(`^coach_request request_id=[a-f0-9]{32} phase=(request|provider_auth|catalog|inference|model_response) status=(200|400|503) duration_ms=[0-9]+$`)
		failure := regexp.MustCompile(`^coach_failure request_id=[a-f0-9]{32} phase=(inference|model_response) code=(inference_failed|invalid_model_response)$`)
		requests, failures := 0, 0
		for _, line := range strings.Split(text, "\n") {
			if strings.HasPrefix(line, "coach_request") {
				requests++
				if !request.MatchString(line) {
					t.Fatal("request log not allowlisted")
				}
			}
			if strings.HasPrefix(line, "coach_failure") {
				failures++
				if !failure.MatchString(line) {
					t.Fatal("failure log not allowlisted")
				}
			}
		}
		if requests != 5 || failures != 2 {
			t.Fatalf("missing actual diagnostics: %d requests, %d failures", requests, failures)
		}
		return
	}
	dir := t.TempDir()
	key := filepath.Join(dir, "key")
	if err := os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PROVIDER_KEY_FILE", key)
	mode := "catalog"
	cfg := &serverConfig{authPath: filepath.Join(dir, "auth.json"), historyPath: filepath.Join(dir, "history.json")}
	cfg.httpClient = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		if strings.Contains(r.URL.Path, "models") {
			if mode == "catalog" {
				return nil, errors.New("PRIVATE_SENTINEL catalog token")
			}
			return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(`{"models":[{"slug":"gpt-6.1-terra","visibility":"list"}]}`))}, nil
		}
		if mode == "inference" {
			return nil, errors.New("PRIVATE_SENTINEL upstream bearer private text")
		}
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(accountTranslationSSE(`{"PRIVATE_SENTINEL":"private model answer"}`, true, "response.completed")))}, nil
	})}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	token, s, err := cfg.auth.store.create("PRIVATE_SENTINEL owner", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	refs := map[string]bool{}
	call := func(body, phase string, status int) {
		r := httptest.NewRequest("POST", "/v1/learning/coach", strings.NewReader(body))
		r.Header.Set("Authorization", "Bearer "+token)
		r.Header.Set("X-Coach-Request-ID", "PRIVATE_SENTINEL untrusted reference")
		r.Header.Set("X-Coach-Phase", "PRIVATE_SENTINEL untrusted phase")
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		ref := w.Header().Get("X-Coach-Request-ID")
		if w.Code != status || w.Header().Get("X-Coach-Phase") != phase || !regexp.MustCompile(`^[a-f0-9]{32}$`).MatchString(ref) || refs[ref] {
			t.Fatalf("diagnostic response mismatch: status=%d phase=%s", w.Code, w.Header().Get("X-Coach-Phase"))
		}
		refs[ref] = true
	}
	body := func(id string) string {
		return `{"request_id":"` + id + `","action":"message","text":"PRIVATE_SENTINEL learner","locale":"en"}`
	}
	call(`{"PRIVATE_SENTINEL":"malformed request"}`, "request", 400)
	call(body("auth"), "provider_auth", 503)
	if err = cfg.provider.save(s.UserID, providerCredential{AccessToken: "PRIVATE_SENTINEL provider credential", Expires: time.Now().Add(time.Hour)}); err != nil {
		t.Fatal(err)
	}
	call(body("catalog"), "catalog", 503)
	history, err := openHistory(filepath.Join(dir, "users", sessionHash(s.UserID)+".json"))
	if err != nil {
		t.Fatal(err)
	}
	if err = history.append(translationRecord{ID: "PRIVATE_SENTINEL_source", CreatedAt: time.Now(), translationInput: translationInput{Text: "PRIVATE_SENTINEL original", SourceLanguage: "en", TargetLanguage: "de"}, translationResult: translationResult{Translation: "PRIVATE_SENTINEL quote"}}); err != nil {
		t.Fatal(err)
	}
	mode = "inference"
	call(body("inference"), "inference", 200)
	mode = "invalid"
	call(body("invalid"), "model_response", 200)
}
