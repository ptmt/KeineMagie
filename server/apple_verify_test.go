package main

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"errors"
	"io"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestAppleJWKSFailedRefreshPreservesCachedKey(t *testing.T) {
	private, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	for _, failure := range []string{"canceled", "network", "status", "malformed", "oversized", "empty", "invalid key"} {
		t.Run(failure, func(t *testing.T) {
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			var calls atomic.Int32
			k := &appleKeys{client: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
				if calls.Add(1) == 1 {
					return (jwksTransport{private}).RoundTrip(r)
				}
				status, body := http.StatusOK, `{`
				switch failure {
				case "canceled":
					cancel()
					<-r.Context().Done()
					return nil, r.Context().Err()
				case "network":
					return nil, errors.New("upstream unavailable")
				case "status":
					status = http.StatusServiceUnavailable
				case "oversized":
					body = strings.Repeat("x", (1<<20)+1)
				case "empty":
					body = `{"keys":[]}`
				case "invalid key":
					body = `{"keys":[{"kid":"apple-test","alg":"RS256","use":"sig","kty":"RSA","n":"AA","e":"AQAB"}]}`
				}
				return &http.Response{StatusCode: status, Body: io.NopCloser(strings.NewReader(body)), Header: http.Header{}}, nil
			})}}
			now := time.Date(2026, time.November, 8, 12, 0, 0, 0, time.UTC)
			cached, err := k.key(context.Background(), "apple-test", now)
			if err != nil {
				t.Fatal(err)
			}
			refreshAt := now.Add(time.Minute)
			if _, err := k.key(ctx, "attacker-kid", refreshAt); err == nil {
				t.Fatal("unknown key accepted after failed refresh")
			}
			got, err := k.key(context.Background(), "apple-test", refreshAt)
			if err != nil || got != cached {
				t.Fatalf("failed %s refresh evicted healthy cached key: key=%v err=%v", failure, got, err)
			}
			for i := 0; i < 100; i++ {
				if _, err := k.key(context.Background(), "another-unknown", refreshAt.Add(time.Second)); err == nil {
					t.Fatal("unknown key accepted during cooldown")
				}
			}
			if got := calls.Load(); got != 2 {
				t.Fatalf("failed refresh bypassed cooldown: %d requests, want 2", got)
			}
		})
	}
}

func TestAppleJWKSFailedRefreshDoesNotExtendTTL(t *testing.T) {
	private, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	var calls atomic.Int32
	k := &appleKeys{client: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		if calls.Add(1) == 1 {
			return (jwksTransport{private}).RoundTrip(r)
		}
		return nil, errors.New("upstream unavailable")
	})}}
	now := time.Date(2026, time.November, 8, 12, 0, 0, 0, time.UTC)
	if _, err := k.key(context.Background(), "apple-test", now); err != nil {
		t.Fatal(err)
	}
	// A failure just before expiry must not renew the cached keys' lifetime.
	if _, err := k.key(context.Background(), "unknown", now.Add(time.Hour-time.Second)); err == nil {
		t.Fatal("unknown key accepted")
	}
	if _, err := k.key(context.Background(), "apple-test", now.Add(time.Hour-time.Nanosecond)); err != nil {
		t.Fatalf("unexpired cached key unavailable: %v", err)
	}
	for _, elapsed := range []time.Duration{time.Hour, time.Hour + time.Minute, 2 * time.Hour} {
		if key, err := k.key(context.Background(), "apple-test", now.Add(elapsed)); err == nil || key != nil {
			t.Fatalf("expired cached key accepted after %s", elapsed)
		}
	}
	if got := calls.Load(); got != 4 {
		t.Fatalf("expiry/cooldown requests = %d, want 4", got)
	}
}

func TestAppleJWKSConcurrentRefreshBounded(t *testing.T) {
	private, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	for _, fail := range []bool{false, true} {
		t.Run(map[bool]string{false: "success", true: "failure"}[fail], func(t *testing.T) {
			var calls atomic.Int32
			started, release := make(chan struct{}), make(chan struct{})
			k := &appleKeys{client: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
				if calls.Add(1) == 2 {
					close(started)
					<-release
					if fail {
						return nil, errors.New("upstream unavailable")
					}
				}
				return (jwksTransport{private}).RoundTrip(r)
			})}}
			now := time.Date(2026, time.November, 8, 12, 0, 0, 0, time.UTC)
			if _, err := k.key(context.Background(), "apple-test", now); err != nil {
				t.Fatal(err)
			}
			now = now.Add(time.Minute)
			var wg sync.WaitGroup
			wg.Add(1)
			go func() {
				defer wg.Done()
				if _, err := k.key(context.Background(), "unknown", now); err == nil {
					t.Error("unknown key accepted")
				}
			}()
			<-started
			for i := 0; i < 32; i++ {
				wg.Add(1)
				go func() {
					defer wg.Done()
					if _, err := k.key(context.Background(), "other-unknown", now); err == nil {
						t.Error("unknown key accepted")
					}
					if _, err := k.key(context.Background(), "apple-test", now); err != nil {
						t.Errorf("cached key unavailable after concurrent refresh: %v", err)
					}
				}()
			}
			close(release)
			wg.Wait()
			if got := calls.Load(); got != 2 {
				t.Fatalf("concurrent refresh requests = %d, want 2", got)
			}
		})
	}
}

func TestAppleJWKSSuccessfulRefreshReplacesCachedKeys(t *testing.T) {
	private, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	var calls atomic.Int32
	k := &appleKeys{client: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		resp, err := (jwksTransport{private}).RoundTrip(r)
		if calls.Add(1) > 1 {
			body, readErr := io.ReadAll(resp.Body)
			resp.Body.Close()
			if readErr != nil {
				return nil, readErr
			}
			resp.Body = io.NopCloser(strings.NewReader(strings.ReplaceAll(string(body), "apple-test", "rotated")))
		}
		return resp, err
	})}}
	now := time.Date(2026, time.November, 8, 12, 0, 0, 0, time.UTC)
	if _, err := k.key(context.Background(), "apple-test", now); err != nil {
		t.Fatal(err)
	}
	refreshed := now.Add(time.Minute)
	// A valid replacement is published even if it lacks the triggering kid.
	if _, err := k.key(context.Background(), "unknown", refreshed); err == nil {
		t.Fatal("unknown key accepted")
	}
	if _, err := k.key(context.Background(), "rotated", refreshed); err != nil {
		t.Fatalf("replacement key unavailable: %v", err)
	}
	if _, err := k.key(context.Background(), "apple-test", refreshed); err == nil {
		t.Fatal("removed key retained after successful refresh")
	}
	if _, err := k.key(context.Background(), "rotated", now.Add(time.Hour)); err != nil {
		t.Fatalf("successful refresh did not renew TTL: %v", err)
	}
	if got := calls.Load(); got != 2 {
		t.Fatalf("successful refresh requests = %d, want 2", got)
	}
}
