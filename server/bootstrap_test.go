package main

import "testing"

func TestBootstrapServerOrigin(t *testing.T) {
	for _, raw := range []string{"http://evil.invalid", "https://example.com/path", "https://user:pass@example.com", "https://example.com?q=x", "file:///x"} {
		if _, err := bootstrapOrigin(raw); err == nil {
			t.Fatalf("accepted unsafe origin %s", raw)
		}
	}
	for _, raw := range []string{"https://example.com", "http://127.0.0.1:8787"} {
		if _, err := bootstrapOrigin(raw); err != nil {
			t.Fatal(err)
		}
	}
}
