package main

import (
	"encoding/json"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"
)

var uuidHostPattern = regexp.MustCompile(`^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)

func TestProviderAuthorizeUsesDocumentedUUIDHost(t *testing.T) {
	key := filepath.Join(t.TempDir(), "key")
	if err := os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PROVIDER_KEY_FILE", key)
	cfg := &serverConfig{authPath: t.TempDir() + "/auth.json", historyPath: t.TempDir() + "/history.json"}
	h, err := newHandler(cfg)
	if err != nil {
		t.Fatal(err)
	}
	token, _, err := cfg.auth.store.create("host-regression", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	w := authCall(h, "POST", "/v1/provider/connect", "{}", token)
	if w.Code != 200 {
		t.Fatalf("connect %d", w.Code)
	}
	var attempt struct {
		Token string `json:"bootstrap_token"`
	}
	json.Unmarshal(w.Body.Bytes(), &attempt)
	body, _ := json.Marshal(map[string]string{"bootstrap_token": attempt.Token, "redirect_uri": "http://127.0.0.1:54321/auth/callback"})
	w = authCall(h, "POST", "/v1/provider/bootstrap/start", string(body), "")
	if w.Code != 200 {
		t.Fatalf("start %d", w.Code)
	}
	var start struct {
		URL string `json:"authorize_url"`
	}
	json.Unmarshal(w.Body.Bytes(), &start)
	u, err := url.Parse(start.URL)
	if err != nil {
		t.Fatal(err)
	}
	q := u.Query()
	if !uuidHostPattern.MatchString(q.Get("ext_agent_host_id")) {
		t.Fatalf("authorize emits invalid UUID host: %q", q.Get("ext_agent_host_id"))
	}
	if q.Get("scope") != "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct" || q.Get("client_id") != "dynamic_agent_client" || q.Get("agent_name_hint") != "KeineMagie" {
		t.Fatal("authorization protocol mismatch")
	}
	p, err := newProvider(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if p.host != q.Get("ext_agent_host_id") {
		t.Fatal("host changed on restart")
	}
}

func TestProviderMigratesOnlyLegacyMalformedUUIDHost(t *testing.T) {
	for _, host := range []string{"urn:uuid:" + strings.Repeat("a", 42) + "Y", "urn:uuid:01234567-89ab-4cde-8fab-0123456789ab", "urn:ietf:params:oauth:jwk-thumbprint:sha-256:example", "did:key:example"} {
		t.Run(host, func(t *testing.T) {
			key := filepath.Join(t.TempDir(), "key")
			if err := os.WriteFile(key, []byte(strings.Repeat("k", 32)), 0600); err != nil {
				t.Fatal(err)
			}
			t.Setenv("PROVIDER_KEY_FILE", key)
			cfg := &serverConfig{authPath: t.TempDir() + "/auth.json", historyPath: t.TempDir() + "/history.json"}
			if _, err := newHandler(cfg); err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(cfg.provider.dir, "host")
			if err := os.WriteFile(path, []byte(host), 0600); err != nil {
				t.Fatal(err)
			}
			p, err := newProvider(cfg)
			if err != nil {
				t.Fatal(err)
			}
			if strings.HasSuffix(host, strings.Repeat("a", 42)+"Y") {
				if !uuidHostPattern.MatchString(p.host) {
					t.Fatalf("legacy malformed host not migrated: %q", p.host)
				}
			} else if p.host != host {
				t.Fatal("existing host identity changed")
			}
			again, err := newProvider(cfg)
			if err != nil {
				t.Fatal(err)
			}
			if again.host != p.host {
				t.Fatal("migration not persisted")
			}
			info, err := os.Stat(path)
			if err != nil {
				t.Fatal(err)
			}
			if info.Mode().Perm() != 0600 {
				t.Fatal("host not owner-only")
			}
		})
	}
}
