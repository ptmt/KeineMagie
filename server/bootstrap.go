package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"
)

func bootstrapOrigin(raw string) (string, error) {
	u, e := url.Parse(strings.TrimSpace(raw))
	if e != nil || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") || u.Host == "" || !(u.Scheme == "https" || (u.Scheme == "http" && u.Hostname() == "127.0.0.1")) {
		return "", errors.New("use an HTTPS server origin (or HTTP 127.0.0.1 for development)")
	}
	return strings.TrimRight(u.String(), "/"), nil
}
func runBootstrap() error {
	reader := bufio.NewReader(os.Stdin)
	fmt.Print("KeineMagie server origin: ")
	raw, e := reader.ReadString('\n')
	if e != nil {
		return e
	}
	origin, e := bootstrapOrigin(raw)
	if e != nil {
		return e
	}
	fmt.Print("One-time connection code (expires after five minutes): ")
	code, e := reader.ReadString('\n')
	if e != nil {
		return e
	}
	code = strings.TrimSpace(code)
	if len(code) != 43 {
		return errors.New("invalid connection code")
	}
	client := &http.Client{Timeout: 60 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	post := func(path string, payload any, result any) error {
		b, _ := json.Marshal(payload)
		resp, err := client.Post(origin+path, "application/json", bytes.NewReader(b))
		if err != nil {
			return errors.New("server connection failed")
		}
		defer resp.Body.Close()
		b, err = io.ReadAll(io.LimitReader(resp.Body, 32769))
		if err != nil || len(b) > 32768 {
			return errors.New("invalid server response")
		}
		if resp.StatusCode != 200 && resp.StatusCode != 204 {
			return fmt.Errorf("connection refused (HTTP %d); create a new code and retry", resp.StatusCode)
		}
		if result != nil {
			return json.Unmarshal(b, result)
		}
		return nil
	}
	listener, e := net.Listen("tcp4", "127.0.0.1:0")
	if e != nil {
		return e
	}
	defer listener.Close()
	redirect := "http://" + listener.Addr().String() + "/auth/callback"
	var start struct {
		URL string `json:"authorize_url"`
	}
	if e = post("/v1/provider/bootstrap/start", map[string]string{"bootstrap_token": code, "redirect_uri": redirect}, &start); e != nil {
		return e
	}
	auth, e := url.Parse(start.URL)
	if e != nil || auth.Scheme != "https" || auth.Host != "auth.openai.com" || auth.Path != "/api/accounts/authorize" || auth.Query().Get("redirect_uri") != redirect {
		return errors.New("server returned an untrusted authorization URL")
	}
	done := make(chan error, 1)
	mux := http.NewServeMux()
	mux.HandleFunc("/auth/callback", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		if r.Method != "GET" || r.Host != listener.Addr().String() {
			http.Error(w, "Invalid callback", 400)
			return
		}
		cb := redirect
		if r.URL.RawQuery != "" {
			cb += "?" + r.URL.RawQuery
		}
		err := post("/v1/provider/bootstrap/complete", map[string]string{"bootstrap_token": code, "callback_url": cb}, nil)
		if err != nil {
			http.Error(w, "Connection failed. Return to the terminal and retry with a new code.", 400)
		} else {
			fmt.Fprint(w, "ChatGPT connected to KeineMagie. Return to your app and refresh connection status.")
		}
		select {
		case done <- err:
		default:
		}
	})
	srv := &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	defer srv.Close()
	go srv.Serve(listener)
	fmt.Println("Continue with ChatGPT in your system browser. This explicitly authorizes your personal self-hosted KeineMagie connection.")
	cmd := "xdg-open"
	if runtime.GOOS == "darwin" {
		cmd = "open"
	}
	if e = exec.Command(cmd, start.URL).Run(); e != nil {
		return errors.New("could not open system browser; authorize URL omitted to protect account hints; configure a browser opener and retry")
	}
	select {
	case e = <-done:
		return e
	case <-time.After(5 * time.Minute):
		return errors.New("connection timed out; create a new code")
	}
}
