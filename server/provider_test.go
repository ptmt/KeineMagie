package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/json"
	"github.com/golang-jwt/jwt/v5"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"
)

func TestProviderDisconnectRevokesRenewableSession(t *testing.T) {
	t.Setenv("PROVIDER_KEY_FILE", t.TempDir()+"/key")
	os.WriteFile(os.Getenv("PROVIDER_KEY_FILE"), []byte(strings.Repeat("k", 32)), 0600)
	revoked := false
	cfg := &serverConfig{authPath: t.TempDir() + "/auth.json", historyPath: t.TempDir() + "/history.json", httpClient: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		body := `{"revocation_endpoint":"https://auth.openai.com/api/accounts/oauth/revoke"}`
		if strings.HasSuffix(r.URL.Path, "/revoke") {
			r.ParseForm()
			if r.Form.Get("token") != "renewable" || r.Form.Get("client_id") != "oaiapp_retained" || r.Form.Get("token_type_hint") != "refresh_token" {
				t.Error("bad revocation grant")
			}
			revoked = true
			body = ""
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(body)), Header: http.Header{}}, nil
	})}}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	token, s, _ := cfg.auth.store.create("owner", time.Now())
	cfg.provider.save(s.UserID, providerCredential{ClientID: "oaiapp_retained", Subject: "owner", AccessToken: "access", RefreshToken: "renewable"})
	w := authCall(h, "POST", "/v1/provider/disconnect", "{}", token)
	if w.Code != 204 || !revoked {
		t.Fatalf("revocation not performed %d", w.Code)
	}
	c, err := cfg.provider.load(s.UserID)
	if err != nil || c.ClientID != "oaiapp_retained" || c.Subject != "owner" || c.AccessToken != "" || c.RefreshToken != "" || c.IDToken != "" {
		t.Fatal("registration not retained without credentials")
	}
}

func TestProviderOAuthValidationAndRefresh(t *testing.T) {
	for _, bad := range []string{"", "nonce", "scope", "subject", "issuer", "audience", "signature"} {
		t.Run(bad, func(t *testing.T) {
			t.Setenv("PROVIDER_KEY_FILE", t.TempDir()+"/key")
			os.WriteFile(os.Getenv("PROVIDER_KEY_FILE"), []byte(strings.Repeat("k", 32)), 0600)
			key, _ := rsa.GenerateKey(rand.Reader, 2048)
			var nonce string
			var refreshing bool
			cfg := &serverConfig{authPath: t.TempDir() + "/auth.json", historyPath: t.TempDir() + "/history.json"}
			cfg.httpClient = &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
				var b []byte
				if strings.Contains(r.URL.Path, "models") {
					return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"models":[{"slug":"synthetic-model","display_name":"Synthetic","visibility":"list"}]}`)), Header: http.Header{}}, nil
				}
				if strings.HasSuffix(r.URL.Path, "jwks.json") {
					resp, _ := (jwksTransport{key}).RoundTrip(httptest.NewRequest("GET", appleJWKSURL, nil))
					return resp, nil
				}
				r.ParseForm()
				if r.Form.Get("client_id") != "oaiapp_registered" || r.Form.Get("resource") != "https://api.openai.com/v1" {
					t.Error("wrong token exchange")
				}
				refreshing = r.Form.Get("grant_type") == "refresh_token"
				claims := jwt.MapClaims{"iss": providerIssuer, "aud": "oaiapp_registered", "sub": "provider-owner", "nonce": nonce, "exp": time.Now().Add(time.Hour).Unix()}
				scope := providerScope
				switch bad {
				case "nonce":
					claims["nonce"] = "wrong"
				case "scope":
					scope = "openid"
				case "subject":
					claims["sub"] = ""
				case "issuer":
					claims["iss"] = "https://evil.invalid"
				case "audience":
					claims["aud"] = "other"
				}
				tok := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
				tok.Header["kid"] = "apple-test"
				signingKey := key
				if bad == "signature" {
					signingKey, _ = rsa.GenerateKey(rand.Reader, 2048)
				}
				raw, _ := tok.SignedString(signingKey)
				access := "first-access"
				refresh := "first-refresh"
				if refreshing {
					access = "rotated-access"
					refresh = "rotated-refresh"
				}
				b, _ = json.Marshal(map[string]any{"access_token": access, "refresh_token": refresh, "id_token": raw, "scope": scope, "token_type": "Bearer", "expires_in": 3600})
				return &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(b)), Header: http.Header{}}, nil
			})}
			h, err := newHandler(cfg)
			if err != nil {
				t.Fatal(err)
			}
			token, s, _ := cfg.auth.store.create("owner", time.Now())
			w := authCall(h, "POST", "/v1/provider/connect", "{}", token)
			var connect struct {
				Token string `json:"bootstrap_token"`
			}
			json.Unmarshal(w.Body.Bytes(), &connect)
			startBody, _ := json.Marshal(map[string]string{"bootstrap_token": connect.Token, "redirect_uri": "http://127.0.0.1:45678/auth/callback"})
			w = authCall(h, "POST", "/v1/provider/bootstrap/start", string(startBody), "")
			var started struct {
				URL string `json:"authorize_url"`
			}
			json.Unmarshal(w.Body.Bytes(), &started)
			u, _ := url.Parse(started.URL)
			nonce = u.Query().Get("nonce")
			cb := "http://127.0.0.1:45678/auth/callback?code=code&client_id=oaiapp_registered&state=" + url.QueryEscape(u.Query().Get("state"))
			body, _ := json.Marshal(map[string]string{"bootstrap_token": connect.Token, "callback_url": cb})
			w = authCall(h, "POST", "/v1/provider/bootstrap/complete", string(body), "")
			if bad != "" {
				if w.Code != 400 {
					t.Fatalf("accepted %s: %d %s", bad, w.Code, w.Body.String())
				}
				if _, err = cfg.provider.load(s.UserID); !os.IsNotExist(err) {
					t.Fatal("invalid grant persisted")
				}
				return
			}
			if w.Code != 204 {
				t.Fatalf("complete %d %s", w.Code, w.Body.String())
			}
			// Synthetic signed OAuth through real persistence, status/catalog and
			// owner history. No external provider or inference is invoked.
			status := authCall(h, "GET", "/v1/provider", "", token)
			var connected struct {
				Connected bool   `json:"connected"`
				Selected  string `json:"selected_model"`
			}
			if status.Code != 200 || json.Unmarshal(status.Body.Bytes(), &connected) != nil || !connected.Connected || connected.Selected != "synthetic-model" {
				t.Fatalf("completed connection not restored: HTTP %d", status.Code)
			}
			if history := authCall(h, "GET", "/v1/translations", "", token); history.Code != 200 {
				t.Fatalf("connected owner history unavailable: HTTP %d", history.Code)
			}
			if w = authCall(h, "POST", "/v1/provider/bootstrap/complete", string(body), ""); w.Code != 401 {
				t.Fatal("replay accepted")
			}
			c, _ := cfg.provider.load(s.UserID)
			c.Expires = time.Now().Add(-time.Second)
			cfg.provider.save(s.UserID, c)
			c, err = cfg.provider.access(context.Background(), s.UserID)
			if err != nil || c.AccessToken != "rotated-access" || c.RefreshToken != "rotated-refresh" || !refreshing {
				t.Fatalf("refresh failed: %v %v", err, c)
			}
		})
	}
}

func TestProviderStreamsRequireCompleted(t *testing.T) {
	for _, tail := range []string{"", "data: {\"type\":\"response.failed\"}\n\n", "data: {\"type\":\"response.incomplete\"}\n\n", "data: [DONE]\n\n"} {
		p := &providerService{client: &http.Client{Transport: transportFunc(func(*http.Request) (*http.Response, error) {
			return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader("data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n" + tail)), Header: http.Header{}}, nil
		})}}
		if _, err := p.translate(context.Background(), "token", "offered", translationInput{}); err == nil {
			t.Fatal("accepted incomplete stream")
		}
	}
	if got := chooseModel([]providerModel{{Slug: "offered"}}); got != "offered" {
		t.Fatal("invented model")
	}
}

func TestProviderCompletedTranslationAndIsolation(t *testing.T) {
	wire := accountTranslationSSE(`{"text":"Привет"}`, true, "response.completed")
	t.Setenv("PROVIDER_KEY_FILE", t.TempDir()+"/key")
	os.WriteFile(os.Getenv("PROVIDER_KEY_FILE"), []byte(strings.Repeat("k", 32)), 0600)
	cfg := &serverConfig{authPath: t.TempDir() + "/auth.json", historyPath: t.TempDir() + "/history.json", httpClient: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		if r.URL.Host == "auth.openai.com" {
			return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"revocation_endpoint":"https://auth.openai.com/api/accounts/oauth/revoke"}`)), Header: http.Header{}}, nil
		}
		if r.Header.Get("Authorization") != "Bearer personal-grant" {
			t.Error("wrong bearer")
		}
		body := `{"models":[{"slug":"other","display_name":"Other","visibility":"list"},{"slug":"gpt-6-luna","display_name":"Luna","visibility":"list"}]}`
		if strings.HasSuffix(r.URL.Path, "/responses") {
			var v map[string]any
			json.NewDecoder(r.Body).Decode(&v)
			if v["store"] != false || v["stream"] != true || v["model"] != "gpt-6-luna" {
				t.Errorf("bad Responses payload %v", v)
			}
			body = wire
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(body)), Header: http.Header{}}, nil
	})}}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	a, sa, err := cfg.auth.store.create("alice", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	b, _, _ := cfg.auth.store.create("bob", time.Now())
	c := providerCredential{ClientID: "oaiapp_test", Subject: "chatgpt-user", AccessToken: "personal-grant", RefreshToken: "refresh-secret", Scope: providerScope, Expires: time.Now().Add(time.Hour)}
	if err = cfg.provider.save(sa.UserID, c); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(cfg.provider.credentialPath(sa.UserID))
	if strings.Contains(string(raw), "personal-grant") || strings.Contains(string(raw), "refresh-secret") {
		t.Fatal("plaintext credential")
	}
	w := authCall(h, "POST", "/v1/translations", `{"text":"Hallo","source_language":"de","target_language":"ru"}`, a)
	var record translationRecord
	if w.Code != 201 || json.Unmarshal(w.Body.Bytes(), &record) != nil || record.Translation != "Привет" {
		t.Fatalf("translation %d %s", w.Code, w.Body.String())
	}
	// Both native and web consume this same response and owner history field.
	w = authCall(h, "GET", "/v1/translations", "", a)
	var history struct {
		Items []translationRecord `json:"items"`
	}
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &history) != nil || len(history.Items) != 1 || history.Items[0].Translation != "Привет" || history.Items[0].ID != record.ID {
		t.Fatalf("clean owner history not persisted: %d %s", w.Code, w.Body.String())
	}
	for _, invalid := range []struct{ output, terminal string }{
		{`{"text":""}`, "response.completed"},
		{`{"text":null}`, "response.completed"},
		{`{"text":"Hallo"} explanation`, "response.completed"},
		{"Es hat funktioniert.", "response.completed"},
		{`{"text":"Hallo"}`, ""},
		{`{"text":"Hallo"}`, "response.failed"},
		{`{"text":"Hallo"}`, "response.incomplete"},
	} {
		wire = accountTranslationSSE(invalid.output, true, invalid.terminal)
		failed := authCall(h, "POST", "/v1/translations", `{"text":"Hallo","source_language":"de","target_language":"ru"}`, a)
		if failed.Code != 502 || strings.Contains(failed.Body.String(), invalid.output) {
			t.Fatalf("invalid upstream did not fail safely: HTTP %d", failed.Code)
		}
	}
	w = authCall(h, "GET", "/v1/translations", "", a)
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &history) != nil || len(history.Items) != 1 || history.Items[0].Translation != "Привет" {
		t.Fatal("failed translations changed owner history")
	}
	if w = authCall(h, "GET", "/v1/translations", "", b); w.Code != 200 || strings.Contains(w.Body.String(), "Привет") {
		t.Fatalf("owner isolation %d %s", w.Code, w.Body.String())
	}
	if w = authCall(h, "POST", "/v1/provider/disconnect", "", b); w.Code != 204 {
		t.Fatal(w.Code)
	}
	if _, err = cfg.provider.load(sa.UserID); err != nil {
		t.Fatal("other user disconnected owner")
	}
	if w = authCall(h, "POST", "/v1/provider/disconnect", "", a); w.Code != 204 {
		t.Fatal(w.Code)
	}
	if retained, err := cfg.provider.load(sa.UserID); err != nil || retained.AccessToken != "" || retained.RefreshToken != "" {
		t.Fatal("credentials retained")
	}
}

func TestProviderAuthenticatedSetupAndOwnerHistory(t *testing.T) {
	h, key, path := signedAuthFixture(t)
	token, _ := sessionResult(t, exchange(t, h, key, getChallenge(t, h), nil))
	if w := authCall(h, "GET", "/v1/provider", "", ""); w.Code != 401 {
		t.Fatalf("provider anonymous: %d", w.Code)
	}
	w := authCall(h, "GET", "/v1/provider", "", token)
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"status":"setup_required"`) {
		t.Fatalf("status %d %s", w.Code, w.Body.String())
	}
	w = authCall(h, "GET", "/v1/translations", "", token)
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"items":[]`) {
		t.Fatalf("private history: %d %s", w.Code, w.Body.String())
	}
	w = authCall(h, "POST", "/v1/provider/connect", "{}", token)
	if w.Code != 503 {
		t.Fatalf("missing encryption key %d", w.Code)
	}
	_ = path
}

func TestProviderBootstrapRequiresLiveOwnerSession(t *testing.T) {
	t.Setenv("PROVIDER_KEY_FILE", t.TempDir()+"/key")
	if err := os.WriteFile(os.Getenv("PROVIDER_KEY_FILE"), []byte(strings.Repeat("k", 32)), 0600); err != nil {
		t.Fatal(err)
	}
	h, key, _ := signedAuthFixture(t)
	token, _ := sessionResult(t, exchange(t, h, key, getChallenge(t, h), nil))
	w := authCall(h, "POST", "/v1/provider/connect", "{}", token)
	if w.Code != 200 {
		t.Fatalf("connect %d %s", w.Code, w.Body.String())
	}
	var v struct {
		Token string `json:"bootstrap_token"`
	}
	json.Unmarshal(w.Body.Bytes(), &v)
	if len(v.Token) != 43 {
		t.Fatal("missing bootstrap code")
	}
	body := `{"bootstrap_token":"` + v.Token + `","redirect_uri":"https://evil.invalid/auth/callback"}`
	if w = authCall(h, "POST", "/v1/provider/bootstrap/start", body, ""); w.Code != 400 {
		t.Fatalf("nonloopback %d", w.Code)
	}
	body = `{"bootstrap_token":"` + v.Token + `","redirect_uri":"http://127.0.0.1:54321/auth/callback"}`
	w = authCall(h, "POST", "/v1/provider/bootstrap/start", body, "")
	if w.Code != 200 || !strings.Contains(w.Body.String(), "dynamic_agent_client") || !strings.Contains(w.Body.String(), "code_challenge=") {
		t.Fatalf("authorize: %d %s", w.Code, w.Body.String())
	}
	authCall(h, "POST", "/v1/auth/logout", "", token)
	if w = authCall(h, "POST", "/v1/provider/bootstrap/complete", `{"bootstrap_token":"`+v.Token+`","callback_url":"http://127.0.0.1:54321/auth/callback?state=bad&code=x&client_id=oaiapp_test"}`, ""); w.Code != 401 {
		t.Fatalf("revoked owner: %d %s", w.Code, w.Body.String())
	}
	_ = http.MethodGet
	_ = time.Second
}
