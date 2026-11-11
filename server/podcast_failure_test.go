package main

import (
	"context"
	"errors"
	"strings"
	"testing"
)

func TestPodcastProviderFailuresHaveSanitizedReasons(t *testing.T) {
	for _, tc := range []struct{ wire, code string }{
		{`{"type":"response.incomplete"}`, "provider_incomplete"},
		{`{"type":"response.refusal.done","refusal":"PRIVATE MODEL CONTENT"}`, "provider_refused"},
		{`{"type":"response.failed","error":{"message":"PRIVATE MODEL CONTENT"}}`, "provider_failed"},
	} {
		_, err := readPodcastTranslationSSE(strings.NewReader("data: " + tc.wire + "\n\n"))
		var failure *podcastFailure
		if !errors.As(err, &failure) || failure.Code != tc.code {
			t.Fatalf("wanted %s, got %v", tc.code, err)
		}
		if strings.Contains(err.Error(), "PRIVATE") {
			t.Fatal("model content leaked")
		}
	}
	f := podcastProviderFailure(context.DeadlineExceeded)
	if f.Code != "provider_timeout" {
		t.Fatal("timeout not classified")
	}
	f = podcastProviderFailure(errors.New("PRIVATE token=secret"))
	if f.Code != "provider_failed" || strings.Contains(f.Error(), "PRIVATE") {
		t.Fatal("unknown failure leaked or lost code")
	}
}
