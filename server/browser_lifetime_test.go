package main

import (
	"bytes"
	"net/http"
	"os"
	"testing"
	"time"
)

// Persisted records from the previous 24-hour policy must retain their deadlines.
func TestBrowserLifetimePreservesExistingSessions(t *testing.T) {
	now := time.Date(2026, 1, 2, 12, 0, 0, 0, time.UTC)
	path := t.TempDir() + "/auth.json"
	store, err := openAuthStore(path)
	if err != nil {
		t.Fatal(err)
	}
	native, owner, err := store.create("existing-owner", now)
	if err != nil {
		t.Fatal(err)
	}
	if !owner.Expires.Equal(now.Add(30*24*time.Hour)) || owner.Kind != "" {
		t.Fatal("native policy changed")
	}
	oldLive, oldExpired := randomAuthToken(), randomAuthToken()
	liveExpiry := now.Add(time.Hour)
	err = store.lock.locked(func() error {
		d, e := store.read()
		if e != nil {
			return e
		}
		d.Sessions[sessionHash(oldLive)] = authSession{Kind: "browser", UserID: owner.UserID, Expires: liveExpiry}
		d.Sessions[sessionHash(oldExpired)] = authSession{Kind: "browser", UserID: owner.UserID, Expires: now}
		return store.write(d)
	})
	if err != nil {
		t.Fatal(err)
	}
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	store, err = openAuthStore(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.lookup(oldExpired, now); err == nil {
		t.Fatal("expired legacy session resurrected")
	}
	old, err := store.lookup(oldLive, now)
	if err != nil || !old.Expires.Equal(liveExpiry) {
		t.Fatal("legacy deadline changed")
	}
	after, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Fatal("reload/lookup migrated existing sessions")
	}
	// A fresh login may prune an expired record, never extend another existing one.
	_, fresh, err := store.createKind("existing-owner", now, "browser")
	if err != nil {
		t.Fatal(err)
	}
	if fresh.UserID != owner.UserID || !fresh.Expires.Equal(now.Add(30*24*time.Hour)) {
		t.Fatal("new login policy/owner incorrect")
	}
	paired, err := store.createBrowser(native, owner.UserID, now)
	if err != nil {
		t.Fatal(err)
	}
	pairedSession, err := store.lookup(paired, now)
	if err != nil || !pairedSession.Expires.Equal(fresh.Expires) {
		t.Fatal("pairing policy differs")
	}
	store, err = openAuthStore(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.lookup(oldExpired, now); err == nil {
		t.Fatal("new login resurrected expired legacy session")
	}
	if _, err = store.lookup(oldLive, liveExpiry); err == nil {
		t.Fatal("new login extended legacy deadline")
	}
	unchanged, err := store.lookup(native, now)
	if err != nil || unchanged != owner {
		t.Fatal("browser login changed native session")
	}
}

// Exercise the cookie actually issued by each login route, not a test-minted session.
func assertBrowserLifetime(t *testing.T, h http.Handler, cfg *serverConfig, cookie *http.Cookie, issued time.Time, origin string) {
	t.Helper()
	const lifetime = 30 * 24 * time.Hour
	if cookie == nil {
		t.Fatal("missing browser session cookie")
	}
	if cookie.MaxAge != int(lifetime/time.Second) || !cookie.Secure || !cookie.HttpOnly || cookie.SameSite != http.SameSiteStrictMode || cookie.Path != "/" || cookie.Domain != "" {
		t.Errorf("browser cookie lifetime/security incorrect (MaxAge=%d)", cookie.MaxAge)
	}
	session, err := cfg.auth.store.lookup(cookie.Value, issued)
	if err != nil {
		t.Fatal(err)
	}
	if session.Kind != "browser" || !session.Expires.Equal(issued.Add(lifetime)) {
		t.Errorf("browser expiry = %s; want %s", session.Expires, issued.Add(lifetime))
	}
	path := cfg.auth.store.lock.path
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		elapsed time.Duration
		status  int
	}{
		{24 * time.Hour, 200}, {24*time.Hour + time.Second, 200}, {lifetime - time.Nanosecond, 200}, {lifetime, 401}, {lifetime + time.Second, 401},
	} {
		cfg.auth.now = func() time.Time { return issued.Add(tc.elapsed) }
		// Reopen the persistent store on every check, as after a backend restart.
		cfg.auth.store, err = openAuthStore(path)
		if err != nil {
			t.Fatal(err)
		}
		w := webAppleCall(h, "GET", "/v1/web/session", "", "", "", []*http.Cookie{cookie})
		if w.Code != tc.status {
			t.Errorf("at %s: status %d, want %d", tc.elapsed, w.Code, tc.status)
		}
		if len(w.Result().Cookies()) != 0 {
			t.Error("session read renewed a cookie")
		}
	}
	after, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Fatal("read/reload changed persisted session: rolling expiry or reset")
	}
	// Move the test clock back only to exercise logout before the absolute deadline.
	cfg.auth.now = func() time.Time { return issued.Add(25 * time.Hour) }
	cookies := []*http.Cookie{cookie}
	for _, bad := range []struct{ origin, csrf string }{{"https://evil.invalid", browserCSRF(cookie.Value)}, {origin, ""}} {
		if w := webAppleCall(h, "POST", "/v1/web/logout", "", bad.origin, bad.csrf, cookies); w.Code != 403 {
			t.Fatalf("unsafe logout accepted: %d", w.Code)
		}
	}
	w := webAppleCall(h, "POST", "/v1/web/logout", "", origin, browserCSRF(cookie.Value), cookies)
	if w.Code != 204 {
		t.Fatalf("logout at 25h: %d", w.Code)
	}
	cleared := false
	for _, c := range w.Result().Cookies() {
		if c.Name == browserCookie {
			cleared = c.MaxAge < 0 && c.Value == "" && c.Secure && c.HttpOnly && c.SameSite == http.SameSiteStrictMode
		}
	}
	if !cleared {
		t.Fatal("logout did not clear secure session cookie")
	}
	cfg.auth.store, err = openAuthStore(path)
	if err != nil {
		t.Fatal(err)
	}
	if w = webAppleCall(h, "GET", "/v1/web/session", "", "", "", cookies); w.Code != 401 {
		t.Fatalf("logout resurrected after reload: %d", w.Code)
	}
}
