package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

// Production handlers/storage/admission/assessment adapter. Only inference is mocked.
func TestManualPlaybackActualHandlerFreezesHybridAssistance(t *testing.T) {
	f := newAssessmentFixture(t)
	call := func(method, path string, body any) []byte {
		t.Helper()
		b, _ := json.Marshal(body)
		w := dictationAssessmentCall(f, method, path, string(b))
		if w.Code != 200 {
			t.Fatalf("%s %s: %d %s", method, path, w.Code, w.Body)
		}
		return w.Body.Bytes()
	}
	var record dictationRecord
	json.Unmarshal(call("POST", "", map[string]any{"id": "manual", "title": "Integration", "text": "Die kleine Katze schläft. Morgen geht sie heim.", "language": "de", "playback_policy_version": 2}), &record)
	for _, s := range record.Plan {
		p := dictationAssetPath(f.cfg.dictationRoot(f.owner), record.ID, s.Asset)
		os.MkdirAll(filepath.Dir(p), 0700)
		if e := os.WriteFile(p, []byte("synthetic cached media"), 0600); e != nil {
			t.Fatal(e)
		}
	}
	var ledger dictationPlayback
	playback := func(id, action string, step, fence int, intent string) {
		json.Unmarshal(call("POST", "/manual/playback", map[string]any{"id": id, "client": "integration", "policy_version": 2, "action": action, "step": step, "fence": fence, "intent": intent}), &ledger)
	}
	playback("lost-start", "start", 0, 0, "planned")
	// Deliberately discard start's ACK. Original stop_base permits exact owned recovery.
	stop := map[string]any{"id": "durable-stop", "client": "integration", "policy_version": 2, "action": "stop", "step": 0, "fence": 0, "admission": "lost-start"}
	json.Unmarshal(call("POST", "/manual/playback", stop), &ledger)
	json.Unmarshal(call("POST", "/manual/playback", stop), &ledger)
	if ledger.Cursor != 0 || ledger.WholeStarts != 1 || len(ledger.Stops) != 1 {
		t.Fatal(ledger)
	}
	for step := 0; step <= 3; step++ {
		id := fmt.Sprint("planned-", step)
		playback(id, "start", step, 0, "planned")
		playback(id, "ended", step, ledger.Active.Fence, "")
	}
	if ledger.Cursor != 4 || ledger.WholeStarts != 2 {
		t.Fatal(ledger)
	}
	playback("extra", "start", 1, 0, "extra")
	playback("extra", "start", 1, 0, "extra") // accepted once, despite lost ACK
	fence := ledger.Active.Fence
	playback("extra", "release", 1, fence, "")
	playback("extra", "resume", 1, ledger.Active.Fence, "")
	playback("extra", "ended", 1, ledger.Active.Fence, "")
	if ledger.Cursor != 4 || ledger.WholeStarts != 2 {
		t.Fatal(ledger)
	}
	call("PUT", "/manual", map[string]any{"revision": 0, "mode": "sentences", "draft": "Die Katze schläft."})
	f.reply = func(*http.Request) (string, error) {
		var pending dictationRecord
		json.Unmarshal(call("GET", "/manual", nil), &pending)
		if pending.Assessment == nil || pending.Assessment.State != "pending" {
			t.Fatal("missing durable pending receipt")
		}
		return accountTranslationSSE(`{"notes":[]}`, true, "response.completed"), nil
	}
	check := map[string]any{"revision": 1, "hybrid": true, "complete": false, "locale": "en"}
	raw := call("POST", "/manual/check", check)
	json.Unmarshal(raw, &record)
	if record.Assessment == nil || record.Assessment.State != "completed" {
		t.Fatalf("%s", raw)
	}
	// Assert actual adapter JSON rather than synthesizing its contract.
	var response struct {
		Assessment struct {
			Assistance struct {
				Tracking string `json:"tracking"`
				Segments []struct {
					Step, Started, Completed, Stopped, Resumes, Interruptions int
					Planned                                                   int `json:"planned_started"`
					Extra                                                     int `json:"extra_requested"`
				} `json:"segments"`
			} `json:"assistance_summary"`
		} `json:"assessment"`
	}
	json.Unmarshal(raw, &response)
	if response.Assessment.Assistance.Tracking != "partial" {
		t.Fatalf("%s", raw)
	}
	found := false
	for _, s := range response.Assessment.Assistance.Segments {
		if s.Step == 1 {
			found = true
			if s.Planned != 3 || s.Extra != 1 || s.Started != 4 || s.Completed != 4 || s.Resumes != 1 || s.Interruptions != 1 {
				t.Fatalf("wrong actual fragment evidence: %+v", s)
			}
		}
	}
	if !found {
		t.Fatalf("missing fragment: %s", raw)
	}
	before, _ := json.Marshal(record.Assessment)
	call("POST", "/manual/check", check)
	f.h, _ = newHandler(f.cfg)
	json.Unmarshal(call("GET", "/manual", nil), &record)
	after, _ := json.Marshal(record.Assessment)
	if string(before) != string(after) || f.calls.Load() != 1 {
		t.Fatal("recovery changed receipt or repeated paid inference")
	}
}
