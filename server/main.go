package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type ttsRequest struct {
	Text         string  `json:"text,omitempty"`
	Input        string  `json:"input,omitempty"`
	Voice        string  `json:"voice,omitempty"`
	Model        string  `json:"model,omitempty"`
	Speed        float64 `json:"speed,omitempty"`
	Format       string  `json:"format,omitempty"`
	Instructions string  `json:"instructions,omitempty"`
	Language     string  `json:"language,omitempty"`
}

type errorResponse struct {
	Error string `json:"error"`
}

type serverConfig struct {
	authPath        string
	appleClientID   string
	appleHTTPClient *http.Client
	auth            *appleAuth
	textModel       string
	historyPath     string
	apiKey          string
	baseURL         string
	model           string
	voice           string
	format          string
	cacheDir        string
	authToken       string
	maxChars        int
	httpClient      *http.Client
}

func main() {
	_ = loadDotEnv(".env")
	cfg, err := loadConfig()
	if err != nil {
		fmt.Fprintf(os.Stderr, "config error: %v\n", err)
		os.Exit(1)
	}

	mux, err := newHandler(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "history error: %v\n", err)
		os.Exit(1)
	}

	addr := listenAddress()
	fmt.Printf("Diktat TTS server listening on %s\n", addr)
	if err := http.ListenAndServe(addr, logRequests(mux)); err != nil {
		fmt.Fprintf(os.Stderr, "server error: %v\n", err)
		os.Exit(1)
	}
}

func loadDotEnv(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}

	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		parts := strings.SplitN(trimmed, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])
		if key == "" {
			continue
		}
		value = strings.Trim(value, `"'`)
		if _, exists := os.LookupEnv(key); !exists {
			_ = os.Setenv(key, value)
		}
	}
	return nil
}

func loadConfig() (*serverConfig, error) {
	apiKey := strings.TrimSpace(os.Getenv("OPENAI_API_KEY"))

	baseURL := strings.TrimSpace(os.Getenv("OPENAI_BASE_URL"))
	if baseURL == "" {
		baseURL = "https://api.openai.com/v1"
	}

	model := strings.TrimSpace(os.Getenv("OPENAI_TTS_MODEL"))
	if model == "" {
		model = "gpt-4o-mini-tts"
	}

	voice := strings.TrimSpace(os.Getenv("OPENAI_TTS_VOICE"))
	if voice == "" {
		voice = "alloy"
	}

	format := strings.ToLower(strings.TrimSpace(os.Getenv("OPENAI_TTS_FORMAT")))
	if format == "" {
		format = "mp3"
	}

	cacheDir := strings.TrimSpace(os.Getenv("TTS_CACHE_DIR"))
	if cacheDir == "" {
		cacheDir = "cache"
	}

	authToken := strings.TrimSpace(os.Getenv("TTS_AUTH_TOKEN"))

	maxChars := 4096
	if value := strings.TrimSpace(os.Getenv("TTS_MAX_CHARS")); value != "" {
		if parsed, err := strconv.Atoi(value); err == nil && parsed > 0 {
			maxChars = parsed
		}
	}

	client := &http.Client{Timeout: 60 * time.Second}

	return &serverConfig{
		authPath:      getenv("AUTH_PATH", "data/auth.json"),
		appleClientID: getenv("APPLE_CLIENT_ID", "de.keinemagie.app"),
		apiKey:        apiKey,
		textModel:     getenv("OPENAI_TEXT_MODEL", "gpt-4o-mini"),
		historyPath:   getenv("HISTORY_PATH", "data/history.json"),
		baseURL:       strings.TrimRight(baseURL, "/"),
		model:         model,
		voice:         voice,
		format:        format,
		cacheDir:      cacheDir,
		authToken:     authToken,
		maxChars:      maxChars,
		httpClient:    client,
	}, nil
}

func (cfg *serverConfig) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"status": "ok",
		"time":   time.Now().Format(time.RFC3339),
	})
}

func (cfg *serverConfig) handleTTS(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	if cfg.sessionProviderPending(w, r) {
		return
	}
	if cfg.authToken == "" {
		writeError(w, http.StatusServiceUnavailable, "TTS_AUTH_TOKEN is required")
		return
	}
	if !authorized(r, cfg.authToken) {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if cfg.apiKey == "" {
		writeError(w, http.StatusServiceUnavailable, "OPENAI_API_KEY is required")
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	defer r.Body.Close()

	var reqBody ttsRequest
	if err := json.NewDecoder(r.Body).Decode(&reqBody); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}

	text := strings.TrimSpace(reqBody.Text)
	if text == "" {
		text = strings.TrimSpace(reqBody.Input)
	}
	if text == "" {
		writeError(w, http.StatusBadRequest, "text is required")
		return
	}

	if runeCount(text) > cfg.maxChars {
		writeError(w, http.StatusBadRequest, fmt.Sprintf("text exceeds %d characters", cfg.maxChars))
		return
	}

	model := strings.TrimSpace(reqBody.Model)
	if model == "" {
		model = cfg.model
	}

	voice := strings.TrimSpace(reqBody.Voice)
	if voice == "" {
		voice = cfg.voice
	}

	format := strings.ToLower(strings.TrimSpace(reqBody.Format))
	if format == "" {
		format = cfg.format
	}

	speed := reqBody.Speed
	if speed <= 0 {
		speed = 1.0
	}
	speed = clamp(speed, 0.25, 4.0)

	instructions := strings.TrimSpace(reqBody.Instructions)
	language := strings.TrimSpace(reqBody.Language)

	cacheKey := buildCacheKey(text, model, voice, format, speed, instructions, language)
	cachePath := filepath.Join(cfg.cacheDir, cacheKey+"."+format)

	if data, ok := readCached(cachePath); ok {
		writeAudio(w, format, data, cacheKey, true)
		return
	}

	audio, err := cfg.fetchSpeech(text, model, voice, format, speed, instructions)
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}

	if err := writeCached(cachePath, audio); err != nil {
		fmt.Fprintf(os.Stderr, "cache write error: %v\n", err)
	}

	writeAudio(w, format, audio, cacheKey, false)
}

func (cfg *serverConfig) fetchSpeech(text, model, voice, format string, speed float64, instructions string) ([]byte, error) {
	payload := map[string]interface{}{
		"model":           model,
		"input":           text,
		"voice":           voice,
		"response_format": format,
		"speed":           speed,
	}

	if instructions != "" && strings.HasPrefix(model, "gpt-4o-mini-tts") {
		payload["instructions"] = instructions
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("failed to encode payload: %w", err)
	}

	url := cfg.baseURL + "/audio/speech"
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+cfg.apiKey)

	resp, err := cfg.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("openai request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		errorBody, _ := io.ReadAll(resp.Body)
		message := strings.TrimSpace(string(errorBody))
		if message == "" {
			message = resp.Status
		}
		return nil, fmt.Errorf("openai error: %s", message)
	}

	audio, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read audio: %w", err)
	}

	return audio, nil
}

func buildCacheKey(text, model, voice, format string, speed float64, instructions, language string) string {
	payload := map[string]interface{}{
		"text":         text,
		"model":        model,
		"voice":        voice,
		"format":       format,
		"speed":        speed,
		"instructions": instructions,
		"language":     language,
	}
	data, _ := json.Marshal(payload)
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func readCached(path string) ([]byte, bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, false
	}
	return data, true
}

func writeCached(path string, data []byte) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}

	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func writeAudio(w http.ResponseWriter, format string, data []byte, cacheKey string, hit bool) {
	contentType := formatContentType(format)
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	w.Header().Set("X-Cache", map[bool]string{true: "HIT", false: "MISS"}[hit])
	w.Header().Set("X-Cache-Key", cacheKey)
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(data)
}

func formatContentType(format string) string {
	switch format {
	case "mp3":
		return "audio/mpeg"
	case "wav":
		return "audio/wav"
	case "flac":
		return "audio/flac"
	case "aac":
		return "audio/aac"
	case "opus":
		return "audio/opus"
	case "pcm":
		return "audio/L16"
	default:
		return "application/octet-stream"
	}
}

func writeJSON(w http.ResponseWriter, status int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, errorResponse{Error: message})
}

func authorized(r *http.Request, token string) bool {
	auth := strings.TrimSpace(r.Header.Get("Authorization"))
	if strings.HasPrefix(strings.ToLower(auth), "bearer ") {
		return strings.TrimSpace(auth[len("bearer "):]) == token
	}
	apiKey := strings.TrimSpace(r.Header.Get("X-API-Key"))
	return apiKey == token
}

func withCORS(handler http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-API-Key")
		handler(w, r)
	}
}

func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		fmt.Printf("%s %s %s\n", r.Method, r.URL.Path, time.Since(start))
	})
}

func clamp(value, min, max float64) float64 {
	if value < min {
		return min
	}
	if value > max {
		return max
	}
	return value
}

func runeCount(value string) int {
	return len([]rune(value))
}

func listenAddress() string {
	return net.JoinHostPort(getenv("HOST", "127.0.0.1"), getenv("PORT", "8787"))
}

func getenv(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}
