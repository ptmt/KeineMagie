package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestLoadConfigWithoutProviderKeyServesHealth(t *testing.T) {
	for _, key := range []string{"", " \t\n"} {
		t.Run("key="+key, func(t *testing.T) {
			t.Setenv("OPENAI_API_KEY", key)
			t.Setenv("TTS_AUTH_TOKEN", "")
			t.Setenv("HISTORY_PATH", t.TempDir()+"/history.json")
			cfg, err := loadConfig()
			if err != nil {
				t.Fatalf("health-only startup: %v", err)
			}
			if cfg.apiKey != "" {
				t.Fatal("missing provider key must remain empty")
			}
			h, err := newHandler(cfg)
			if err != nil {
				t.Fatal(err)
			}
			w := httptest.NewRecorder()
			h.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/health", nil))
			if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"status":"ok"`) {
				t.Fatalf("health: %d %s", w.Code, w.Body.String())
			}
		})
	}
}

func TestLoadConfigTranslationDefaultsAndBindAddress(t *testing.T) {
	t.Setenv("OPENAI_API_KEY", "test-key")
	t.Setenv("OPENAI_TEXT_MODEL", "")
	t.Setenv("HISTORY_PATH", "")
	t.Setenv("HOST", "")
	t.Setenv("PORT", "")
	cfg, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.textModel != "gpt-4o-mini" || cfg.historyPath != "data/history.json" {
		t.Fatalf("translation defaults model=%q path=%q", cfg.textModel, cfg.historyPath)
	}
	if got := listenAddress(); got != "127.0.0.1:8787" {
		t.Fatalf("bind %q", got)
	}
	t.Setenv("OPENAI_TEXT_MODEL", "custom-model")
	t.Setenv("HISTORY_PATH", "private/history.json")
	t.Setenv("HOST", "::1")
	t.Setenv("PORT", "9999")
	cfg, err = loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.textModel != "custom-model" || cfg.historyPath != "private/history.json" || listenAddress() != "[::1]:9999" {
		t.Fatal("configuration overrides ignored")
	}
}

func TestTTSExistingAudioPayloadAndCache(t *testing.T) {
	calls := 0
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if r.URL.Path != "/audio/speech" || r.Header.Get("Authorization") != "Bearer test-key" {
			t.Errorf("bad upstream %s", r.URL.Path)
		}
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
		}
		if body["model"] != "gpt-4o-mini-tts" || body["input"] != "Hallo" || body["voice"] != "alloy" || body["response_format"] != "mp3" || body["speed"] != 1.0 {
			t.Errorf("payload %+v", body)
		}
		_, _ = w.Write([]byte("explicit-fake-test-audio"))
	}))
	defer upstream.Close()
	cfg := &serverConfig{apiKey: "test-key", baseURL: upstream.URL, model: "gpt-4o-mini-tts", voice: "alloy", format: "mp3", authToken: "test-token", cacheDir: t.TempDir(), maxChars: 4096, httpClient: upstream.Client()}
	for _, cache := range []string{"MISS", "HIT"} {
		r := httptest.NewRequest("POST", "/tts", strings.NewReader(`{"input":"Hallo"}`))
		r.Header.Set("Authorization", "Bearer test-token")
		w := httptest.NewRecorder()
		cfg.handleTTS(w, r)
		if w.Code != 200 || w.Body.String() != "explicit-fake-test-audio" || w.Header().Get("X-Cache") != cache || w.Header().Get("Content-Type") != "audio/mpeg" {
			t.Fatalf("TTS %d %s %v", w.Code, w.Body.String(), w.Header())
		}
	}
	if calls != 1 {
		t.Fatalf("upstream calls %d", calls)
	}
}

func TestTTSFailsClosedWithoutProviderKey(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("missing provider key reached upstream")
		w.WriteHeader(http.StatusBadGateway)
	}))
	defer upstream.Close()
	cfg := &serverConfig{authToken: "test-token", baseURL: upstream.URL, httpClient: upstream.Client(), cacheDir: t.TempDir(), model: "gpt-4o-mini-tts", voice: "alloy", format: "mp3", maxChars: 4096}
	for _, cached := range []bool{false, true} {
		if cached {
			key := buildCacheKey("Hallo", cfg.model, cfg.voice, cfg.format, 1, "", "")
			if err := writeCached(cfg.cacheDir+"/"+key+".mp3", []byte("explicit-test-cache")); err != nil {
				t.Fatal(err)
			}
		}
		r := httptest.NewRequest(http.MethodPost, "/tts", strings.NewReader(`{"text":"Hallo"}`))
		r.Header.Set("Authorization", "Bearer test-token")
		w := httptest.NewRecorder()
		cfg.handleTTS(w, r)
		if w.Code != http.StatusServiceUnavailable {
			t.Errorf("cached=%v: got %d, want 503: %s", cached, w.Code, w.Body.String())
		}
	}
}

func TestTTSFailsClosedWithoutToken(t *testing.T) {
	cfg := &serverConfig{}
	r := httptest.NewRequest(http.MethodPost, "/tts", strings.NewReader(`{}`))
	w := httptest.NewRecorder()
	cfg.handleTTS(w, r)
	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("missing configured token: got %d, want 503", w.Code)
	}
}

func TestTTSAuthAndHealthCompatibility(t *testing.T) {
	cfg := &serverConfig{authToken: "test-token"}
	for _, auth := range []string{"", "Bearer wrong"} {
		r := httptest.NewRequest(http.MethodPost, "/tts", strings.NewReader(`{}`))
		r.Header.Set("Authorization", auth)
		w := httptest.NewRecorder()
		cfg.handleTTS(w, r)
		if w.Code != http.StatusUnauthorized {
			t.Fatalf("got %d, want 401", w.Code)
		}
	}
	r := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()
	cfg.handleHealth(w, r)
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"status":"ok"`) {
		t.Fatalf("health: %d %s", w.Code, w.Body.String())
	}
}
