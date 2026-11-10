package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestGermanProofreadingRejectsUnexpectedEnrichment(t *testing.T) {
	cfg := &serverConfig{baseURL: "https://fixture.invalid", httpClient: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"choices":[{"message":{"content":` + strconvQuote(translationFixture) + `}}]}`))}, nil
	})}}
	_, err := cfg.fetchTranslation(httptest.NewRequest("POST", "/", nil), translationInput{Text: "Hallo", SourceLanguage: "de", TargetLanguage: "de"})
	if err == nil {
		t.Fatal("proofreading accepted translation enrichment")
	}
}
