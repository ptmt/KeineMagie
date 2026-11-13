package main

import (
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestLearningAnalysisFailureReturnsSafeStageCode(t *testing.T) {
	cfg, h, token, _, j := learningFixture(t)
	cfg.provider.key = make([]byte, 32)
	session, _ := cfg.auth.store.lookup(token, time.Now())
	if e := cfg.provider.save(session.UserID, providerCredential{AccessToken: "synthetic", Expires: time.Now().Add(time.Hour)}); e != nil {
		t.Fatal(e)
	}
	calls := 0
	cfg.provider.client = &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		if r.Method == "GET" {
			return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"models":[{"slug":"gpt-4o","visibility":"list"}]}`)), Header: http.Header{}}, nil
		}
		calls++
		event := `{"type":"response.completed","response":{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"private invalid output"}]}]}}`
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader("data: " + event + "\n\n")), Header: http.Header{}}, nil
	})}
	path := "/v1/learning/episodes/" + j.ID + "/analysis"
	w := authCall(h, "POST", path, `{}`, token)
	var result struct {
		Code string `json:"code"`
	}
	json.Unmarshal(w.Body.Bytes(), &result)
	if w.Code != 502 || result.Code != "analysis_invalid_output" || strings.Contains(w.Body.String(), "private invalid output") {
		t.Fatalf("missing safe stage code: %d %s", w.Code, w.Body.String())
	}
	w = authCall(h, "GET", path, "", token)
	var view learningAnalysisView
	json.Unmarshal(w.Body.Bytes(), &view)
	if calls != 1 || view.CompletedSteps != 0 || view.Result != nil {
		t.Fatalf("failure charged/replayed or fabricated checkpoint: calls=%d steps=%d", calls, view.CompletedSteps)
	}
}
