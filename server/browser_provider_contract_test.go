package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"
)

// Signed synthetic Apple consent produces a real cookie, not a forged browser bearer.
func TestSignedAppleBrowserProviderSharesNativeOwner(t *testing.T) {
	key := t.TempDir() + "/provider.key"
	if err := os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PROVIDER_KEY_FILE", key)
	h, cfg, apple := webAppleFixture(t)
	q, cookies := startWebApple(t, h)
	apple.nonce = q.Get("nonce")
	w := webAppleCall(h, "POST", "/v1/auth/apple/callback", url.Values{"state": {q.Get("state")}, "code": {"synthetic-code"}}.Encode(), "https://appleid.apple.com", "", cookies)
	if w.Code != 303 {
		t.Fatalf("signed callback %d", w.Code)
	}
	cookies = w.Result().Cookies()
	_, native, err := cfg.auth.store.create("apple-subject", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	browserToken := ""
	for _, c := range cookies {
		if c.Name == browserCookie {
			browserToken = c.Value
		}
	}
	browser, err := cfg.auth.store.lookup(browserToken, time.Now())
	if err != nil || browser.UserID != native.UserID {
		t.Fatal("signed Apple identities differ")
	}
	otherToken, other, err := cfg.auth.store.create("other-owner", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if err = cfg.provider.save(native.UserID, providerCredential{AccessToken: "synthetic-private", Expires: time.Now().Add(time.Hour)}); err != nil {
		t.Fatal(err)
	}
	catalogs := 0
	catalogStatus := 200
	cfg.provider.client = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		if r.URL.String() != "https://api.openai.com/v1/models" || r.Method != "GET" || r.Header.Get("Authorization") != "Bearer synthetic-private" {
			t.Fatal("unexpected provider request")
		}
		catalogs++
		return &http.Response{StatusCode: catalogStatus, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(`{"models":[{"slug":"offered-fixture","display_name":"Fixture","visibility":"list"}]}`))}, nil
	})}
	call := func(path string) { w = webAppleCall(h, "GET", path, "", "", "", cookies) } // browser GET normally has no Origin
	call("/v1/web/session")
	if w.Code != 200 || strings.Contains(w.Body.String(), `"provider"`) || catalogs != 0 {
		t.Fatal("session must be local-only")
	}
	call("/v1/provider")
	var status struct {
		Connected bool   `json:"connected"`
		Status    string `json:"status"`
		Model     string `json:"selected_model"`
	}
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &status) != nil || !status.Connected || status.Model != "offered-fixture" {
		t.Fatalf("cookie provider contract HTTP %d", w.Code)
	}
	if w.Header().Get("Cache-Control") != "no-store" || strings.Contains(w.Body.String(), "synthetic-private") {
		t.Fatal("provider privacy")
	}
	catalogStatus = 401
	call("/v1/provider")
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &status) != nil || !status.Connected || status.Status != "catalog_unavailable" || status.Model != "" {
		t.Fatal("upstream catalog auth failure is not browser expiry")
	}
	call("/v1/web/session")
	if w.Code != 200 {
		t.Fatal("catalog failure revoked browser")
	}
	if w = authCall(h, "GET", "/v1/provider", "", otherToken); w.Code != 200 || strings.Contains(w.Body.String(), `"connected":true`) {
		t.Fatal("provider crossed owner")
	}
	if other.UserID == native.UserID {
		t.Fatal("fixture owners not distinct")
	}
	if w = webAppleCall(h, "POST", "/v1/provider/disconnect", "{}", "https://keinemagie.tinyserve.org", "", cookies); w.Code != 403 {
		t.Fatal("missing mutation CSRF accepted")
	}
	if w = authCall(h, "GET", "/v1/provider", "", browserToken); w.Code != 401 {
		t.Fatal("browser bearer bypass")
	}
	expired := time.Now().Add(-31 * 24 * time.Hour)
	expiredToken, err := cfg.auth.store.createBrowser(otherToken, other.UserID, expired)
	if err != nil {
		t.Fatal(err)
	}
	expiredCookies := []*http.Cookie{{Name: browserCookie, Value: expiredToken}}
	if w = webAppleCall(h, "GET", "/v1/provider", "", "", "", expiredCookies); w.Code != 401 {
		t.Fatal("expired browser authorized")
	}
	if w = webAppleCall(h, "GET", "/v1/provider", "", "", "", nil); w.Code != 401 {
		t.Fatal("guest authorized")
	}
}
