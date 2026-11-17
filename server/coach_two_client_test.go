package main

import (
	"encoding/json"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// Opt-in bridge for two real AppModels against one authenticated Go fixture.
func TestCoachTwoClientBridge(t *testing.T) {
	dir := os.Getenv("KM_COACH_TWO_CLIENT_DIR")
	if dir == "" {
		t.Skip("two-client runner not active")
	}
	f := newAssessmentFixture(t)
	if err := f.cfg.coachStore(f.owner).transaction(true, func(d *coachData) error {
		old := time.Now().Add(-5*time.Hour - time.Minute)
		d.LastVisit = &old
		d.LastNudge = d.LastVisit
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{Handler: f.h, ReadHeaderTimeout: 5 * time.Second}
	defer server.Close()
	go server.Serve(listener)
	data, _ := json.Marshal(map[string]string{"url": "http://" + listener.Addr().String(), "token": f.token, "owner": f.owner})
	if err := os.WriteFile(filepath.Join(dir, "ready.json"), data, 0600); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(90 * time.Second)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(filepath.Join(dir, "stop")); err == nil {
			if f.calls.Load() != 1 {
				t.Errorf("two entries plus one explicit assessment: provider requests=%d, want 1", f.calls.Load())
			}
			if d := f.read(t); len(d.DailyClaims) != 1 || d.DailyClaims[0].TurnID != "one" {
				t.Error("daily resume claim not shared durably")
			}
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatal("two-client runner did not finish")
}
