package main

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

var errDictationConfig = errors.New("explicit OpenAI speech provider, dedicated credential and approved limits required")

// No default budgets, ambient OPENAI_API_KEY, OAuth or alternative model.
func dictationLoadOpenAI() (dictationOpenAIConfig, error) {
	c := dictationOpenAIConfig{model: os.Getenv("DICTATION_OPENAI_MODEL"), voice: os.Getenv("DICTATION_OPENAI_VOICE")}
	if os.Getenv("DICTATION_TTS_PROVIDER") != "openai-realtime" || c.model != "gpt-realtime-2.1-mini" {
		return c, errDictationConfig
	}
	switch c.voice {
	case "alloy", "ash", "ballad", "coral", "echo", "sage", "shimmer", "verse", "marin", "cedar":
	default:
		return c, errDictationConfig
	}
	for _, v := range []struct {
		name    string
		target  *int
		ceiling int
	}{
		{"MAX_CHARS", &c.chars, 1800}, {"MAX_SECONDS", &c.seconds, 180}, {"MAX_OUTPUT_TOKENS", &c.tokens, 4096}, {"TIMEOUT_SECONDS", &c.timeout, 240},
		{"DAILY_CHARS", &c.dailyChars, 1000000}, {"DAILY_SECONDS", &c.dailySeconds, 86400}, {"DAILY_REQUESTS", &c.dailyRequests, 10000},
	} {
		n, e := strconv.Atoi(os.Getenv("DICTATION_OPENAI_" + v.name))
		if e != nil || n < 1 || n > v.ceiling {
			return c, errDictationConfig
		}
		*v.target = n
	}
	if os.Getenv("DICTATION_OPENAI_CONCURRENCY") != "1" {
		return c, errDictationConfig
	}
	c.key = os.Getenv("DICTATION_OPENAI_API_KEY")
	if p := os.Getenv("DICTATION_OPENAI_API_KEY_FILE"); p != "" {
		if c.key != "" || !filepath.IsAbs(p) {
			return c, errDictationConfig
		}
		f, e := os.Open(p)
		if e != nil {
			return c, errDictationConfig
		}
		defer f.Close()
		info, e := f.Stat()
		if e != nil || !info.Mode().IsRegular() || info.Size() > 4096 {
			return c, errDictationConfig
		}
		b, e := io.ReadAll(io.LimitReader(f, 4097))
		if e != nil || len(b) > 4096 {
			return c, errDictationConfig
		}
		c.key = strings.TrimSpace(string(b))
	}
	if c.key == "" || len(c.key) > 4096 || strings.ContainsAny(c.key, "\r\n \t") {
		return c, errDictationConfig
	}
	return c, nil
}
