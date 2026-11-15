package main

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// Explicit administrator-provided local executable. No provider keys/fallbacks.
func dictationLegacyTTSAvailable() bool {
	if socket := os.Getenv("DICTATION_TTS_SOCKET"); socket != "" {
		info, err := os.Stat(socket)
		return filepath.IsAbs(socket) && err == nil && info.Mode()&os.ModeSocket != 0
	}
	p := os.Getenv("DICTATION_TTS_EXECUTABLE")
	if !filepath.IsAbs(p) {
		return false
	}
	// Advertise only a configured executable AND readable German model/config.
	model := os.Getenv("DICTATION_MODEL")
	if !filepath.IsAbs(model) {
		return false
	}
	for _, path := range []string{model, model + ".json"} {
		f, err := os.Open(path)
		if err != nil {
			return false
		}
		f.Close()
	}
	s, e := os.Stat(p)
	return e == nil && !s.IsDir() && s.Mode()&0111 != 0
}

type dictationLimitedBuffer struct{ bytes.Buffer }

func (b *dictationLimitedBuffer) Write(p []byte) (int, error) {
	if b.Len()+len(p) > 16<<20 {
		return 0, errors.New("audio limit")
	}
	return b.Buffer.Write(p)
}
func dictationLegacySynthesize(ctx context.Context, text string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, 40*time.Second)
	defer cancel()
	if socket := os.Getenv("DICTATION_TTS_SOCKET"); socket != "" {
		transport := &http.Transport{DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "unix", socket)
		}}
		defer transport.CloseIdleConnections()
		client := &http.Client{Transport: transport, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
		req, err := http.NewRequestWithContext(ctx, "POST", "http://private-tts/synthesize", strings.NewReader(text))
		if err != nil {
			return nil, err
		}
		req.Header.Set("Content-Type", "text/plain; charset=utf-8")
		response, err := client.Do(req)
		if err != nil {
			return nil, err
		}
		defer response.Body.Close()
		if response.StatusCode != 200 {
			return nil, errors.New("private speech worker unavailable")
		}
		b, err := io.ReadAll(io.LimitReader(response.Body, (16<<20)+1))
		if err != nil {
			return nil, err
		}
		if len(b) < 44 || len(b) > 16<<20 || string(b[:4]) != "RIFF" || string(b[8:12]) != "WAVE" {
			return nil, errors.New("invalid WAV")
		}
		return b, nil
	}
	cmd := exec.CommandContext(ctx, os.Getenv("DICTATION_TTS_EXECUTABLE"))
	cmd.Env = []string{"PATH=/usr/local/bin:/usr/bin:/bin", "DICTATION_MODEL=" + os.Getenv("DICTATION_MODEL"), "HOME=/nonexistent", "OMP_NUM_THREADS=2", "OPENBLAS_NUM_THREADS=2"}
	cmd.Stdin = strings.NewReader(text)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return nil
		}
		return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
	}
	cmd.WaitDelay = time.Second
	var out dictationLimitedBuffer
	cmd.Stdout = &out
	cmd.Stderr = io.Discard
	if e := cmd.Run(); e != nil {
		return nil, e
	}
	b := out.Bytes()
	if len(b) < 44 || string(b[:4]) != "RIFF" || string(b[8:12]) != "WAVE" {
		return nil, errors.New("invalid WAV")
	}
	return b, nil
}
