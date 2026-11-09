package main

import (
	"strings"
	"testing"
)

func TestWebAdvertisesRegistrationGateWithoutNativeTokenFallback(t *testing.T) {
	h := authHandler(t)
	w := authCall(h, "GET", "/v1/web/config", "", "")
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"apple_available":false`) || !strings.Contains(w.Body.String(), `"chatgpt_connect_available":false`) || w.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("web gate %d %s", w.Code, w.Body.String())
	}
	if w = authCall(h, "GET", "/v1/web/session", "", ""); w.Code != 401 {
		t.Fatalf("unconfigured browser session %d", w.Code)
	}
}
