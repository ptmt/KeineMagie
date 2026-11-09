package main

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"github.com/golang-jwt/jwt/v5"
	"io"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func authHandler(t *testing.T) http.Handler {
	t.Helper()
	t.Setenv("AUTH_PATH", t.TempDir()+"/auth.json")
	t.Setenv("HISTORY_PATH", t.TempDir()+"/history.json")
	cfg, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	return h
}
func authCall(h http.Handler, method, path, body, token string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	r.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}
func TestAppleChallengeContract(t *testing.T) {
	h := authHandler(t)
	seen := map[string]bool{}
	for i := 0; i < 2; i++ {
		w := authCall(h, "POST", "/v1/auth/apple/challenge", "", "")
		if w.Code != 200 {
			t.Fatalf("challenge: %d %s", w.Code, w.Body.String())
		}
		if w.Header().Get("Cache-Control") != "no-store" {
			t.Fatal("missing no-store")
		}
		var c map[string]string
		if err := json.Unmarshal(w.Body.Bytes(), &c); err != nil {
			t.Fatal(err)
		}
		if len(c) != 3 {
			t.Fatalf("unexpected contract %v", c)
		}
		for _, k := range []string{"challenge_id", "nonce", "state"} {
			if len(c[k]) < 43 || seen[c[k]] {
				t.Fatalf("not independent random %s", k)
			}
			seen[c[k]] = true
		}
	}
}

type jwksTransport struct{ key *rsa.PrivateKey }

func (s jwksTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	if r.URL.String() != "https://appleid.apple.com/auth/keys" {
		panic("untrusted JWKS destination")
	}
	b, _ := json.Marshal(map[string]any{"keys": []any{map[string]string{"kty": "RSA", "alg": "RS256", "use": "sig", "kid": "apple-test", "n": base64.RawURLEncoding.EncodeToString(s.key.N.Bytes()), "e": base64.RawURLEncoding.EncodeToString(big.NewInt(int64(s.key.E)).Bytes())}}})
	return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(string(b))), Header: http.Header{}}, nil
}
func signedAuthFixture(t *testing.T) (http.Handler, *rsa.PrivateKey, string) {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	path := t.TempDir() + "/auth.json"
	cfg := &serverConfig{historyPath: t.TempDir() + "/history.json", authPath: path, appleClientID: "de.keinemagie.app", appleHTTPClient: &http.Client{Transport: jwksTransport{key}}}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	return h, key, path
}
func getChallenge(t *testing.T, h http.Handler) map[string]string {
	t.Helper()
	w := authCall(h, "POST", "/v1/auth/apple/challenge", "", "")
	if w.Code != 200 {
		t.Fatalf("challenge %d", w.Code)
	}
	var c map[string]string
	json.Unmarshal(w.Body.Bytes(), &c)
	return c
}
func exchange(t *testing.T, h http.Handler, key *rsa.PrivateKey, c map[string]string, change func(jwt.MapClaims)) *httptest.ResponseRecorder {
	t.Helper()
	claims := jwt.MapClaims{"iss": "https://appleid.apple.com", "aud": "de.keinemagie.app", "sub": "apple-subject", "iat": time.Now().Unix(), "exp": time.Now().Add(time.Hour).Unix(), "nonce": c["nonce"]}
	if change != nil {
		change(claims)
	}
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	token.Header["kid"] = "apple-test"
	signed, err := token.SignedString(key)
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(map[string]string{"challenge_id": c["challenge_id"], "identity_token": signed, "state": c["state"]})
	return authCall(h, "POST", "/v1/auth/apple", string(b), "")
}
func TestAppleSignedExchangeCreatesOpaqueSession(t *testing.T) {
	h, key, path := signedAuthFixture(t)
	w := exchange(t, h, key, getChallenge(t, h), nil)
	if w.Code != 200 {
		t.Fatalf("exchange %d %s", w.Code, w.Body.String())
	}
	var result struct {
		Token string `json:"session_token"`
		User  struct {
			ID string `json:"id"`
		} `json:"user"`
		Expires time.Time `json:"expires_at"`
	}
	json.Unmarshal(w.Body.Bytes(), &result)
	if len(result.Token) < 43 || result.User.ID == "" || time.Until(result.Expires) < 29*24*time.Hour {
		t.Fatalf("bad session %s", w.Body.String())
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), result.Token) {
		t.Fatal("raw token persisted")
	}
	s := authCall(h, "GET", "/v1/auth/session", "", result.Token)
	if s.Code != 200 || !strings.Contains(s.Body.String(), result.User.ID) {
		t.Fatalf("session %d %s", s.Code, s.Body.String())
	}
}

func sessionResult(t *testing.T, w *httptest.ResponseRecorder) (string, string) {
	t.Helper()
	if w.Code != 200 {
		t.Fatalf("exchange %d %s", w.Code, w.Body.String())
	}
	var v struct {
		Token string `json:"session_token"`
		User  struct {
			ID string `json:"id"`
		} `json:"user"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
		t.Fatal(err)
	}
	return v.Token, v.User.ID
}
func TestAppleSignedTokenNegatives(t *testing.T) {
	h, key, _ := signedAuthFixture(t)
	cases := map[string]func(jwt.MapClaims){
		"issuer":          func(c jwt.MapClaims) { c["iss"] = "https://evil.invalid" },
		"audience":        func(c jwt.MapClaims) { c["aud"] = "other" },
		"extra audience":  func(c jwt.MapClaims) { c["aud"] = []string{"de.keinemagie.app", "other"} },
		"expired":         func(c jwt.MapClaims) { c["exp"] = time.Now().Add(-time.Second).Unix() },
		"missing expiry":  func(c jwt.MapClaims) { delete(c, "exp") },
		"future issued":   func(c jwt.MapClaims) { c["iat"] = time.Now().Add(time.Hour).Unix() },
		"missing issued":  func(c jwt.MapClaims) { delete(c, "iat") },
		"empty subject":   func(c jwt.MapClaims) { c["sub"] = "" },
		"blank subject":   func(c jwt.MapClaims) { c["sub"] = "  " },
		"missing subject": func(c jwt.MapClaims) { delete(c, "sub") },
		"nonce":           func(c jwt.MapClaims) { c["nonce"] = "wrong" },
		"missing nonce":   func(c jwt.MapClaims) { delete(c, "nonce") },
	}
	for name, change := range cases {
		t.Run(name, func(t *testing.T) {
			c := getChallenge(t, h)
			w := exchange(t, h, key, c, change)
			if w.Code != 401 || w.Header().Get("Cache-Control") != "no-store" {
				t.Fatalf("accepted invalid token %d %s", w.Code, w.Body.String())
			}
			if exchange(t, h, key, c, nil).Code != 401 {
				t.Fatal("failed attempt not consumed")
			}
		})
	}
	wrong, _ := rsa.GenerateKey(rand.Reader, 2048)
	if exchange(t, h, wrong, getChallenge(t, h), nil).Code != 401 {
		t.Fatal("wrong signature accepted")
	}
}
func TestAppleSessionPersistenceLogout(t *testing.T) {
	h, key, path := signedAuthFixture(t)
	token, id := sessionResult(t, exchange(t, h, key, getChallenge(t, h), nil))
	cfg := &serverConfig{authPath: path, historyPath: t.TempDir() + "/history.json", appleHTTPClient: &http.Client{Transport: jwksTransport{key}}}
	restart, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if authCall(restart, "GET", "/v1/auth/session", "", token).Code != 200 {
		t.Fatal("session lost on restart")
	}
	_, id2 := sessionResult(t, exchange(t, restart, key, getChallenge(t, restart), func(c jwt.MapClaims) { c["email"] = "untrusted@example.org" }))
	if id != id2 {
		t.Fatal("unstable user")
	}
	w := authCall(restart, "POST", "/v1/auth/logout", "", token)
	if w.Code != 204 {
		t.Fatalf("logout %d", w.Code)
	}
	if authCall(h, "GET", "/v1/auth/session", "", token).Code != 401 {
		t.Fatal("revocation not visible across stores")
	}
	for _, p := range []string{path, path + ".lock"} {
		info, err := os.Stat(p)
		if err != nil || info.Mode().Perm() != 0600 {
			t.Fatalf("private file %s %v", p, err)
		}
	}
}

func TestAppleNewSessionsCannotUseSharedProviderOrHistory(t *testing.T) {
	h, key, path := signedAuthFixture(t)
	token, _ := sessionResult(t, exchange(t, h, key, getChallenge(t, h), nil))
	for _, legacy := range []string{"", "explicit-legacy"} {
		cfg := &serverConfig{authPath: path, historyPath: t.TempDir() + "/history.json", authToken: legacy, apiKey: "must-not-use", baseURL: "http://127.0.0.1:1"}
		h, err := newHandler(cfg)
		if err != nil {
			t.Fatal(err)
		}
		for _, route := range []struct{ method, path string }{{"GET", "/v1/translations"}, {"POST", "/v1/translations"}, {"POST", "/tts"}} {
			w := authCall(h, route.method, route.path, `{"text":"Hallo"}`, token)
			if route.method == "GET" && route.path == "/v1/translations" {
				if w.Code != 200 || !strings.Contains(w.Body.String(), `"items":[]`) {
					t.Fatalf("private history boundary: %d %s", w.Code, w.Body.String())
				}
				continue
			}
			if route.path == "/v1/translations" && w.Code == 400 {
				continue
			} // Invalid language pair is rejected before provider access.
			if w.Code != 503 || !strings.Contains(w.Body.String(), "provider connection pending") || w.Header().Get("Cache-Control") != "no-store" {
				t.Fatalf("new session crossed legacy boundary: %d %s", w.Code, w.Body.String())
			}
		}
	}
}
func TestAppleChallengeBoundedAndRateLimited(t *testing.T) {
	cfg := &serverConfig{authPath: t.TempDir() + "/auth.json"}
	a, err := newAppleAuth(cfg)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	a.now = func() time.Time { return now }
	for i := 0; i < 21; i++ {
		w := httptest.NewRecorder()
		a.challenge(w, httptest.NewRequest("POST", "/v1/auth/apple/challenge", nil))
		if i == 20 && w.Code != 429 {
			t.Fatalf("unbounded IP rate %d", w.Code)
		}
	}
	now = now.Add(time.Minute)
	for i := 0; i < 1024; i++ {
		a.challenges[randomAuthToken()] = appleChallenge{expires: now.Add(time.Minute)}
	}
	w := httptest.NewRecorder()
	a.challenge(w, httptest.NewRequest("POST", "/v1/auth/apple/challenge", nil))
	if w.Code != 429 {
		t.Fatalf("unbounded challenge store %d", w.Code)
	}
	now = now.Add(5 * time.Minute)
	w = httptest.NewRecorder()
	a.challenge(w, httptest.NewRequest("POST", "/v1/auth/apple/challenge", nil))
	if w.Code != 200 || len(a.challenges) != 1 {
		t.Fatalf("expired challenges not reclaimed %d %d", w.Code, len(a.challenges))
	}
}

func TestAppleReplayConcurrentAndExpiry(t *testing.T) {
	h, key, _ := signedAuthFixture(t)
	c := getChallenge(t, h)
	var wg sync.WaitGroup
	var success atomic.Int32
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			w := exchange(t, h, key, c, nil)
			if w.Code == 200 {
				success.Add(1)
			} else if w.Code != 401 {
				t.Errorf("unexpected status %d", w.Code)
			}
		}()
	}
	wg.Wait()
	if success.Load() != 1 {
		t.Fatalf("exchange won %d times", success.Load())
	}
	c = getChallenge(t, h)
	c["state"] = "wrong"
	if exchange(t, h, key, c, nil).Code != 401 {
		t.Fatal("state accepted")
	}
	cfg := &serverConfig{authPath: t.TempDir() + "/auth.json", appleHTTPClient: &http.Client{Transport: jwksTransport{key}}}
	a, err := newAppleAuth(cfg)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	a.now = func() time.Time { return now }
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/auth/apple/challenge", a.challenge)
	mux.HandleFunc("/v1/auth/apple", a.exchange)
	c = getChallenge(t, mux)
	now = now.Add(5 * time.Minute)
	if exchange(t, mux, key, c, nil).Code != 401 {
		t.Fatal("expired challenge accepted")
	}
	token, _, err := a.store.create("expiring-subject", now)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = a.store.lookup(token, now.Add(30*24*time.Hour)); err == nil {
		t.Fatal("expired session accepted")
	}
}
func TestAppleUntrustedAlgorithmsAndHeaders(t *testing.T) {
	h, key, _ := signedAuthFixture(t)
	for _, mode := range []string{"none", "HS256", "RS384", "missing kid", "unknown kid", "untrusted jku"} {
		t.Run(mode, func(t *testing.T) {
			c := getChallenge(t, h)
			claims := jwt.MapClaims{"iss": "https://appleid.apple.com", "aud": "de.keinemagie.app", "sub": "sub", "exp": time.Now().Add(time.Hour).Unix(), "iat": time.Now().Unix(), "nonce": c["nonce"]}
			method := jwt.SigningMethod(jwt.SigningMethodRS256)
			var signingKey any = key
			switch mode {
			case "none":
				method = jwt.SigningMethodNone
				signingKey = jwt.UnsafeAllowNoneSignatureType
			case "HS256":
				method = jwt.SigningMethodHS256
				signingKey = []byte("untrusted-secret")
			case "RS384":
				method = jwt.SigningMethodRS384
			}
			token := jwt.NewWithClaims(method, claims)
			token.Header["kid"] = "apple-test"
			if mode == "missing kid" {
				delete(token.Header, "kid")
			}
			if mode == "unknown kid" || mode == "untrusted jku" {
				token.Header["kid"] = "evil"
				token.Header["jku"] = "https://evil.invalid/keys"
				token.Header["x5u"] = "http://127.0.0.1/keys"
			}
			raw, err := token.SignedString(signingKey)
			if err != nil {
				t.Fatal(err)
			}
			b, _ := json.Marshal(map[string]string{"challenge_id": c["challenge_id"], "identity_token": raw, "state": c["state"]})
			w := authCall(h, "POST", "/v1/auth/apple", string(b), "")
			if w.Code != 401 {
				t.Fatalf("accepted %s %d", mode, w.Code)
			}
		})
	}
}

type countingKeys struct {
	key   *rsa.PrivateKey
	calls atomic.Int32
}

func (s *countingKeys) RoundTrip(r *http.Request) (*http.Response, error) {
	s.calls.Add(1)
	return (jwksTransport{s.key}).RoundTrip(r)
}
func TestAppleUnknownKeyRefreshBounded(t *testing.T) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	transport := &countingKeys{key: key}
	k := &appleKeys{client: &http.Client{Transport: transport}}
	now := time.Now()
	if _, err = k.key(context.Background(), "apple-test", now); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 100; i++ {
		if _, err = k.key(context.Background(), fmt.Sprint("unknown-", i), now); err == nil {
			t.Fatal("unknown key accepted")
		}
	}
	if transport.calls.Load() != 1 {
		t.Fatal("unbounded refresh")
	}
	if _, err = k.key(context.Background(), "unknown", now.Add(time.Minute)); err == nil {
		t.Fatal("unknown accepted")
	}
	if transport.calls.Load() != 2 {
		t.Fatal("rotation refresh absent")
	}
}
func TestAppleExchangeRateLimit(t *testing.T) {
	h := authHandler(t)
	for i := 0; i < 61; i++ {
		w := authCall(h, "POST", "/v1/auth/apple", `{"challenge_id":"unknown","identity_token":"invalid","state":"invalid"}`, "")
		if i == 60 && w.Code != 429 {
			t.Fatalf("exchange rate unbounded: %d", w.Code)
		}
	}
}

func TestAppleAuthConfig(t *testing.T) {
	t.Setenv("AUTH_PATH", "")
	t.Setenv("APPLE_CLIENT_ID", "")
	cfg, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.authPath != "data/auth.json" || cfg.appleClientID != "de.keinemagie.app" {
		t.Fatal("incorrect native defaults")
	}
	t.Setenv("AUTH_PATH", "private/apple.json")
	t.Setenv("APPLE_CLIENT_ID", "custom.native.bundle")
	cfg, err = loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.authPath != "private/apple.json" || cfg.appleClientID != "custom.native.bundle" {
		t.Fatal("overrides ignored")
	}
}
func TestAppleMalformedRequestsAndSessionErrors(t *testing.T) {
	h := authHandler(t)
	for _, route := range []struct{ method, path string }{{"GET", "/v1/auth/apple/challenge"}, {"GET", "/v1/auth/apple"}, {"POST", "/v1/auth/session"}, {"GET", "/v1/auth/logout"}} {
		w := authCall(h, route.method, route.path, "", "")
		if w.Code != 405 || w.Header().Get("Cache-Control") != "no-store" {
			t.Fatalf("method %d %v", w.Code, w.Header())
		}
	}
	for _, body := range []string{`{}`, `null`, `{"authorization_code":"never accepted"}`, `{} {}`, strings.Repeat("x", 20000)} {
		w := authCall(h, "POST", "/v1/auth/apple", body, "")
		if w.Code != 400 && w.Code != 401 {
			t.Fatalf("malformed %d", w.Code)
		}
		if w.Header().Get("Cache-Control") != "no-store" {
			t.Fatal("cacheable auth error")
		}
	}
	for _, path := range []string{"/v1/auth/session", "/v1/auth/logout"} {
		method := "GET"
		if strings.HasSuffix(path, "logout") {
			method = "POST"
		}
		w := authCall(h, method, path, "", "invalid")
		if w.Code != 401 || w.Header().Get("Cache-Control") != "no-store" {
			t.Fatal("invalid session accepted")
		}
	}
}
func TestAppleAuthStoreConcurrentProcessesAndCorruption(t *testing.T) {
	path := t.TempDir() + "/auth.json"
	s1, err := openAuthStore(path)
	if err != nil {
		t.Fatal(err)
	}
	s2, err := openAuthStore(path)
	if err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	ids := make(chan string, 20)
	tokens := make(chan string, 20)
	now := time.Now()
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			s := s1
			if i%2 == 0 {
				s = s2
			}
			token, v, err := s.create("same-subject", now)
			if err != nil {
				t.Error(err)
				return
			}
			ids <- v.UserID
			tokens <- token
		}(i)
	}
	wg.Wait()
	close(ids)
	close(tokens)
	stable := ""
	for id := range ids {
		if stable != "" && id != stable {
			t.Fatal("race changed user mapping")
		}
		stable = id
	}
	for token := range tokens {
		if _, err = s1.lookup(token, now); err != nil {
			t.Fatal("lost session")
		}
	}
	if err = os.WriteFile(path, []byte(`{"users":null}`), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err = openAuthStore(path); err == nil {
		t.Fatal("corruption accepted")
	}
	if _, _, err = s1.create("subject", now); err == nil {
		t.Fatal("overwrote corrupt data")
	}
}

type transportFunc func(*http.Request) (*http.Response, error)

func (f transportFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestAppleJWKSFailuresFailClosed(t *testing.T) {
	for _, body := range []string{`{`, `{"keys":[]}`, `{"keys":[{"kid":"x","alg":"RS256","use":"sig","kty":"RSA","n":"AA","e":"AQAB"}]}`, strings.Repeat("x", (1<<20)+1)} {
		k := &appleKeys{client: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
			return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(body)), Header: http.Header{}}, nil
		})}}
		if _, err := k.key(context.Background(), "x", time.Now()); err == nil {
			t.Fatal("invalid key accepted")
		}
	}
	a, err := newAppleAuth(&serverConfig{authPath: t.TempDir() + "/auth.json", appleHTTPClient: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 302, Body: io.NopCloser(strings.NewReader("")), Header: http.Header{"Location": []string{"https://evil.invalid/keys"}}}, nil
	})}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = a.keys.key(context.Background(), "x", time.Now()); err == nil {
		t.Fatal("redirect accepted")
	}
}

func TestAppleLegacy43CharacterTokenStillExplicitlySupported(t *testing.T) {
	token := strings.Repeat("l", 43)
	cfg := &serverConfig{authPath: t.TempDir() + "/auth.json", historyPath: t.TempDir() + "/history.json", authToken: token}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	w := authCall(h, "GET", "/v1/translations", "", token)
	if w.Code != 200 {
		t.Fatalf("explicit legacy regression %d", w.Code)
	}
}

func TestAppleRateLimitedAttemptConsumesChallenge(t *testing.T) {
	h, key, _ := signedAuthFixture(t)
	c := getChallenge(t, h)
	for i := 0; i < 60; i++ {
		authCall(h, "POST", "/v1/auth/apple", `{"challenge_id":"unknown"}`, "")
	}
	if exchange(t, h, key, c, nil).Code != 429 {
		t.Fatal("missing rate limit")
	}
	// A new peer must not be able to reuse the challenge rejected at the limit.
	claims := jwt.MapClaims{"iss": "https://appleid.apple.com", "aud": "de.keinemagie.app", "sub": "sub", "exp": time.Now().Add(time.Hour).Unix(), "iat": time.Now().Unix(), "nonce": c["nonce"]}
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	token.Header["kid"] = "apple-test"
	raw, err := token.SignedString(key)
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(map[string]string{"challenge_id": c["challenge_id"], "state": c["state"], "identity_token": raw})
	r := httptest.NewRequest("POST", "/v1/auth/apple", strings.NewReader(string(b)))
	r.RemoteAddr = "192.0.2.20:1234"
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 401 {
		t.Fatalf("rate-limited challenge reusable %d", w.Code)
	}
}

func TestAppleExistingLockPermissionsArePrivate(t *testing.T) {
	path := t.TempDir() + "/auth.json"
	if err := os.WriteFile(path+".lock", nil, 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := openAuthStore(path); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path + ".lock")
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0600 {
		t.Fatalf("lock permissions %o", info.Mode().Perm())
	}
}
