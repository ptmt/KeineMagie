package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const testAppleCallback = "https://keinemagie.tinyserve.org/v1/auth/apple/callback"
const testWebID = "test.synthetic.apple.web"

func TestAppleWebRejectsUnboundCallbacks(t *testing.T) {
	h, _, transport := webAppleFixture(t)
	q, cookies := startWebApple(t, h)
	transport.nonce = q.Get("nonce")
	body := url.Values{"state": {q.Get("state")}, "code": {"synthetic-code"}}.Encode()
	for _, tc := range []struct {
		name, origin, body string
		cookies            []*http.Cookie
		status             int
	}{
		{"missing cookie", "https://appleid.apple.com", body, nil, 401},
		{"other browser", "https://appleid.apple.com", body, []*http.Cookie{{Name: "__Host-km-apple", Value: randomAuthToken()}}, 401},
		{"wrong state", "https://appleid.apple.com", "state=wrong&code=synthetic-code", cookies, 401},
		{"bad origin", "https://evil.invalid", body, cookies, 403},
		{"duplicate state", "https://appleid.apple.com", body + "&state=other", cookies, 400},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := webAppleCall(h, "POST", "/v1/auth/apple/callback", tc.body, tc.origin, "", tc.cookies)
			if w.Code != tc.status {
				t.Fatalf("status %d", w.Code)
			}
		})
	}
	if transport.calls != 0 {
		t.Fatal("unbound callback reached Apple")
	}
	// A forged request must not consume the actual browser's transaction.
	w := webAppleCall(h, "POST", "/v1/auth/apple/callback", body, "https://appleid.apple.com", "", cookies)
	if w.Code != 303 {
		t.Fatalf("legitimate callback lost: %d", w.Code)
	}
}

func TestAppleWebRejectsInvalidSignedTokensAndExchange(t *testing.T) {
	for _, tc := range []struct {
		name    string
		change  func(jwt.MapClaims)
		failure bool
	}{
		{"wrong audience", func(c jwt.MapClaims) { c["aud"] = "de.keinemagie.app" }, false},
		{"wrong issuer", func(c jwt.MapClaims) { c["iss"] = "https://evil.invalid" }, false},
		{"wrong nonce", func(c jwt.MapClaims) { c["nonce"] = "wrong" }, false},
		{"expired", func(c jwt.MapClaims) { c["exp"] = time.Now().Add(-time.Hour).Unix() }, false},
		{"empty subject", func(c jwt.MapClaims) { c["sub"] = "" }, false},
		{"exchange error", nil, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			h, _, transport := webAppleFixture(t)
			q, cookies := startWebApple(t, h)
			transport.nonce = q.Get("nonce")
			transport.change = tc.change
			transport.failure = tc.failure
			body := url.Values{"state": {q.Get("state")}, "code": {"synthetic-code"}}.Encode()
			for i := 0; i < 2; i++ {
				w := webAppleCall(h, "POST", "/v1/auth/apple/callback", body, "https://appleid.apple.com", "", cookies)
				if w.Code != 401 {
					t.Fatalf("accepted bad token: %d", w.Code)
				}
				for _, c := range w.Result().Cookies() {
					if c.Name == browserCookie && c.MaxAge > 0 {
						t.Fatal("session minted")
					}
				}
			}
			if transport.calls != 1 {
				t.Fatal("failed exchange replayed")
			}
		})
	}
}

func TestAppleWebExpiryCancelAndLogout(t *testing.T) {
	for _, mode := range []string{"expiry", "cancel", "logout"} {
		t.Run(mode, func(t *testing.T) {
			h, cfg, transport := webAppleFixture(t)
			q, cookies := startWebApple(t, h)
			transport.nonce = q.Get("nonce")
			body := url.Values{"state": {q.Get("state")}, "code": {"synthetic-code"}}.Encode()
			switch mode {
			case "expiry":
				cfg.auth.now = func() time.Time { return time.Now().Add(6 * time.Minute) }
			case "cancel":
				w := webAppleCall(h, "POST", "/v1/auth/apple/callback", url.Values{"state": {q.Get("state")}, "error": {"access_denied"}}.Encode(), "https://appleid.apple.com", "", cookies)
				if w.Code != 401 {
					t.Fatalf("cancel %d", w.Code)
				}
			case "logout":
				token, _, err := cfg.auth.store.createKind("apple-subject", time.Now(), "browser")
				if err != nil {
					t.Fatal(err)
				}
				cookies = append(cookies, &http.Cookie{Name: browserCookie, Value: token})
				w := webAppleCall(h, "POST", "/v1/web/logout", "", "https://evil.invalid", browserCSRF(token), cookies)
				if w.Code != 403 {
					t.Fatal("cross-site logout accepted")
				}
				w = webAppleCall(h, "POST", "/v1/web/logout", "", "https://keinemagie.tinyserve.org", browserCSRF(token), cookies)
				if w.Code != 204 {
					t.Fatalf("logout %d", w.Code)
				}
				if _, err := cfg.auth.store.lookup(token, time.Now()); err == nil {
					t.Fatal("logout did not revoke")
				}
			}
			w := webAppleCall(h, "POST", "/v1/auth/apple/callback", body, "https://appleid.apple.com", "", cookies)
			if w.Code != 401 || transport.calls != 0 {
				t.Fatalf("resurrected: %d exchanges=%d", w.Code, transport.calls)
			}
		})
	}
}

func TestAppleWebStartRequiresSameOriginCSRF(t *testing.T) {
	h, _, _ := webAppleFixture(t)
	for _, method := range []string{"GET", "POST"} {
		w := webAppleCall(h, method, "/v1/auth/apple/start", "", "https://evil.invalid", "", nil)
		if w.Code != 403 && w.Code != 405 {
			t.Fatalf("start %s: %d", method, w.Code)
		}
	}
}

func TestAppleWebConfigurationGates(t *testing.T) {
	_, cfg, _ := webAppleFixture(t)
	for _, field := range []string{"APPLE_WEB_CLIENT_ID", "APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY_FILE"} {
		t.Run(field, func(t *testing.T) {
			t.Setenv(field, "")
			h, err := newHandler(cfg)
			if err != nil {
				t.Fatal(err)
			}
			w := webAppleCall(h, "GET", "/v1/web/config", "", "", "", nil)
			var c struct {
				Available bool `json:"apple_available"`
				Pair      bool `json:"pairing_available"`
			}
			if err := json.Unmarshal(w.Body.Bytes(), &c); err != nil {
				t.Fatal(err)
			}
			if c.Available || !c.Pair {
				t.Fatal("incomplete config advertised")
			}
			w = webAppleCall(h, "POST", "/v1/auth/apple/start", "", "https://keinemagie.tinyserve.org", "", nil)
			if w.Code != 503 {
				t.Fatalf("ungated route %d", w.Code)
			}
		})
	}
	for _, tc := range []struct{ field, value string }{{"APPLE_WEB_CLIENT_ID", "de.keinemagie.app"}, {"APPLE_TEAM_ID", "bad"}, {"APPLE_KEY_ID", "bad"}, {"APPLE_PRIVATE_KEY_FILE", "/nonexistent/private.p8"}, {"WEB_ORIGIN", "https://evil.invalid"}} {
		t.Run(tc.field+tc.value, func(t *testing.T) {
			t.Setenv(tc.field, tc.value)
			if _, err := newHandler(cfg); err == nil {
				t.Fatal("invalid complete config accepted")
			}
		})
	}
}

func TestAppleWebNeverLinksByEmail(t *testing.T) {
	h, cfg, transport := webAppleFixture(t)
	q, cookies := startWebApple(t, h)
	transport.nonce = q.Get("nonce")
	transport.change = func(c jwt.MapClaims) { c["email"] = "same@example.invalid" }
	body := url.Values{"state": {q.Get("state")}, "code": {"synthetic-code"}}.Encode()
	w := webAppleCall(h, "POST", "/v1/auth/apple/callback", body, "https://appleid.apple.com", "", cookies)
	if w.Code != 303 {
		t.Fatalf("login %d", w.Code)
	}
	var first authSession
	for _, c := range w.Result().Cookies() {
		if c.Name == browserCookie {
			var err error
			first, err = cfg.auth.store.lookup(c.Value, time.Now())
			if err != nil {
				t.Fatal(err)
			}
		}
	}
	q, cookies = startWebApple(t, h)
	transport.nonce = q.Get("nonce")
	transport.change = func(c jwt.MapClaims) { c["sub"] = "other-apple-subject"; c["email"] = "same@example.invalid" }
	body = url.Values{"state": {q.Get("state")}, "code": {"synthetic-code"}}.Encode()
	w = webAppleCall(h, "POST", "/v1/auth/apple/callback", body, "https://appleid.apple.com", "", cookies)
	if w.Code != 303 {
		t.Fatalf("second login %d", w.Code)
	}
	for _, c := range w.Result().Cookies() {
		if c.Name == browserCookie {
			second, err := cfg.auth.store.lookup(c.Value, time.Now())
			if err != nil || second.UserID == first.UserID {
				t.Fatal("linked accounts by email")
			}
		}
	}
}

func TestAppleWebConcurrentReplay(t *testing.T) {
	h, _, transport := webAppleFixture(t)
	q, cookies := startWebApple(t, h)
	transport.nonce = q.Get("nonce")
	body := url.Values{"state": {q.Get("state")}, "code": {"synthetic-code"}}.Encode()
	results := make(chan *httptest.ResponseRecorder, 8)
	for i := 0; i < 8; i++ {
		go func() {
			results <- webAppleCall(h, "POST", "/v1/auth/apple/callback", body, "https://appleid.apple.com", "", cookies)
		}()
	}
	success := 0
	for i := 0; i < 8; i++ {
		w := <-results
		if w.Code == 303 {
			success++
		} else if w.Code != 401 {
			t.Fatalf("unexpected %d", w.Code)
		}
	}
	if success != 1 || transport.calls != 1 {
		t.Fatalf("double consumption successes=%d exchanges=%d", success, transport.calls)
	}
}

type appleWebTransport struct {
	t       *testing.T
	signing *ecdsa.PrivateKey
	apple   *rsa.PrivateKey
	nonce   string
	change  func(jwt.MapClaims)
	failure bool
	calls   int
}

func (s *appleWebTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	if r.URL.String() == appleJWKSURL {
		return (jwksTransport{s.apple}).RoundTrip(r)
	}
	if r.URL.String() != "https://appleid.apple.com/auth/token" {
		s.t.Fatalf("unexpected destination %s", r.URL)
	}
	s.calls++
	if err := r.ParseForm(); err != nil {
		s.t.Fatal(err)
	}
	if r.Method != "POST" || r.PostForm.Get("client_id") != testWebID || r.PostForm.Get("redirect_uri") != testAppleCallback || r.PostForm.Get("grant_type") != "authorization_code" || r.PostForm.Get("code") != "synthetic-code" || r.PostForm.Get("code_verifier") != "" {
		s.t.Fatalf("bad token request %v", r.PostForm)
	}
	claims := jwt.MapClaims{}
	token, err := jwt.ParseWithClaims(r.PostForm.Get("client_secret"), claims, func(token *jwt.Token) (any, error) { return &s.signing.PublicKey, nil }, jwt.WithValidMethods([]string{"ES256"}), jwt.WithIssuer("49PJNAT2WC"), jwt.WithAudience("https://appleid.apple.com"), jwt.WithSubject(testWebID), jwt.WithExpirationRequired())
	if err != nil || token.Header["kid"] != "TESTKEY123" {
		s.t.Fatalf("invalid client secret: %v", err)
	}
	if s.failure {
		return &http.Response{StatusCode: 400, Body: io.NopCloser(strings.NewReader(`{"error":"invalid_grant"}`)), Header: http.Header{}}, nil
	}
	c := jwt.MapClaims{"iss": "https://appleid.apple.com", "aud": testWebID, "sub": "apple-subject", "nonce": s.nonce, "iat": time.Now().Unix(), "exp": time.Now().Add(time.Hour).Unix()}
	if s.change != nil {
		s.change(c)
	}
	id := jwt.NewWithClaims(jwt.SigningMethodRS256, c)
	id.Header["kid"] = "apple-test"
	signed, err := id.SignedString(s.apple)
	if err != nil {
		s.t.Fatal(err)
	}
	body, _ := json.Marshal(map[string]string{"id_token": signed, "access_token": "never-expose", "refresh_token": "never-persist"})
	return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(string(body))), Header: http.Header{}}, nil
}
func webAppleFixture(t *testing.T) (http.Handler, *serverConfig, *appleWebTransport) {
	t.Helper()
	t.Setenv("WEB_ORIGIN", "https://keinemagie.tinyserve.org")
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	raw, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	path := t.TempDir() + "/key.p8"
	if err = os.WriteFile(path, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: raw}), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("APPLE_WEB_CLIENT_ID", testWebID)
	t.Setenv("APPLE_TEAM_ID", "49PJNAT2WC")
	t.Setenv("APPLE_KEY_ID", "TESTKEY123")
	t.Setenv("APPLE_PRIVATE_KEY_FILE", path)
	t.Setenv("AUTH_PATH", t.TempDir()+"/auth.json")
	t.Setenv("HISTORY_PATH", t.TempDir()+"/history.json")
	apple, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	transport := &appleWebTransport{t: t, signing: key, apple: apple}
	cfg, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	cfg.appleHTTPClient = &http.Client{Transport: transport}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	return h, cfg, transport
}
func webAppleCall(h http.Handler, method, path, body, origin, csrf string, cookies []*http.Cookie) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, "https://keinemagie.tinyserve.org"+path, strings.NewReader(body))
	r.Header.Set("Origin", origin)
	r.Header.Set("X-CSRF-Token", csrf)
	if method == "POST" {
		r.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	}
	for _, c := range cookies {
		r.AddCookie(c)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}
func startWebApple(t *testing.T, h http.Handler) (url.Values, []*http.Cookie) {
	t.Helper()
	w := webAppleCall(h, "GET", "/v1/web/config", "", "", "", nil)
	var boot struct {
		Available bool   `json:"apple_available"`
		CSRF      string `json:"csrf_token"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &boot); err != nil {
		t.Fatal(err)
	}
	if !boot.Available {
		t.Fatalf("Apple web not enabled: %s", w.Body.String())
	}
	w = webAppleCall(h, "POST", "/v1/auth/apple/start", "", "https://keinemagie.tinyserve.org", boot.CSRF, w.Result().Cookies())
	if w.Code != 200 {
		t.Fatalf("start: %d %s", w.Code, w.Body.String())
	}
	var result struct {
		URL string `json:"authorization_url"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	u, err := url.Parse(result.URL)
	if err != nil {
		t.Fatal(err)
	}
	q := u.Query()
	if u.Scheme != "https" || u.Host != "appleid.apple.com" || u.Path != "/auth/authorize" || q.Get("client_id") != testWebID || q.Get("redirect_uri") != testAppleCallback || q.Get("response_type") != "code" || q.Get("response_mode") != "form_post" || len(q.Get("state")) != 43 || len(q.Get("nonce")) != 43 || q.Get("state") == q.Get("nonce") || q.Get("code_challenge") != "" {
		t.Fatalf("bad authorization URL: %s", u)
	}
	cookies := w.Result().Cookies()
	if len(cookies) != 1 || cookies[0].Name != "__Host-km-apple" || !cookies[0].Secure || !cookies[0].HttpOnly || cookies[0].SameSite != http.SameSiteNoneMode || cookies[0].Path != "/" || cookies[0].Domain != "" || cookies[0].MaxAge != 300 {
		t.Fatalf("unsafe transaction cookies: %v", cookies)
	}
	return q, cookies
}
func TestAppleWebSignedCodeLogin(t *testing.T) {
	h, cfg, transport := webAppleFixture(t)
	_, native, err := cfg.auth.store.create("apple-subject", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	q, cookies := startWebApple(t, h)
	transport.nonce = q.Get("nonce")
	body := url.Values{"state": {q.Get("state")}, "code": {"synthetic-code"}}.Encode()
	w := webAppleCall(h, "POST", "/v1/auth/apple/callback", body, "https://appleid.apple.com", "", cookies)
	if w.Code != 303 || w.Header().Get("Location") != "/" {
		t.Fatalf("callback: %d %s", w.Code, w.Body.String())
	}
	var sessionCookie *http.Cookie
	for _, c := range w.Result().Cookies() {
		if c.Name == browserCookie {
			sessionCookie = c
		}
	}
	if sessionCookie == nil || !sessionCookie.Secure || !sessionCookie.HttpOnly || sessionCookie.SameSite != http.SameSiteStrictMode {
		t.Fatalf("unsafe session: %v", sessionCookie)
	}
	session, err := cfg.auth.store.lookup(sessionCookie.Value, time.Now())
	if err != nil || session.Kind != "browser" || session.UserID != native.UserID || time.Until(session.Expires) > 24*time.Hour {
		t.Fatalf("not linked to native: %+v %v", session, err)
	}
	if transport.calls != 1 || strings.Contains(w.Body.String(), sessionCookie.Value) || strings.Contains(w.Header().Get("Location"), "token") {
		t.Fatal("credential leakage")
	}
	w = webAppleCall(h, "POST", "/v1/auth/apple/callback", body, "https://appleid.apple.com", "", cookies)
	if w.Code != 401 || transport.calls != 1 {
		t.Fatalf("replayed: %d calls=%d", w.Code, transport.calls)
	}
}
