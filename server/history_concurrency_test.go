package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestHistoryConcurrentAppendFavoriteDeleteNoLostUpdates(t *testing.T) {
	_, h, token, _, store := historyFixture(t)
	const count = 24
	for i := 0; i < count; i++ {
		if err := store.append(translationRecord{ID: fmt.Sprintf("favorite-%d", i)}); err != nil {
			t.Fatal(err)
		}
		if err := store.append(translationRecord{ID: fmt.Sprintf("delete-%d", i)}); err != nil {
			t.Fatal(err)
		}
	}
	var wg sync.WaitGroup
	for i := 0; i < count; i++ {
		wg.Add(3)
		go func(i int) {
			defer wg.Done()
			w := authCall(h, "PATCH", fmt.Sprintf("/v1/history/favorite-%d", i), `{"favorite":true}`, token)
			if w.Code != 200 {
				t.Errorf("favorite %d %s", w.Code, w.Body.String())
			}
		}(i)
		go func(i int) {
			defer wg.Done()
			w := authCall(h, "DELETE", fmt.Sprintf("/v1/history/delete-%d", i), "", token)
			if w.Code != 204 {
				t.Errorf("delete %d %s", w.Code, w.Body.String())
			}
		}(i)
		go func(i int) {
			defer wg.Done()
			separate, err := openHistory(store.path)
			if err != nil {
				t.Error(err)
				return
			}
			if err := separate.append(translationRecord{ID: fmt.Sprintf("append-%d", i)}); err != nil {
				t.Error(err)
			}
		}(i)
	}
	wg.Wait()
	reopened, err := openHistory(store.path)
	if err != nil {
		t.Fatal(err)
	}
	items, err := reopened.list()
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != count*2+1 {
		t.Fatalf("lost updates: %d", len(items))
	}
	for _, item := range items {
		if strings.HasPrefix(item.ID, "delete-") {
			t.Errorf("resurrected %s", item.ID)
		}
		if strings.HasPrefix(item.ID, "favorite-") && !item.Favorite {
			t.Errorf("lost favorite %s", item.ID)
		}
	}
}

func TestHistoryMutationWriteFailureDoesNotReportSuccess(t *testing.T) {
	for _, method := range []string{"PATCH", "DELETE"} {
		t.Run(method, func(t *testing.T) {
			_, h, token, _, store := historyFixture(t)
			before, err := os.ReadFile(store.path)
			if err != nil {
				t.Fatal(err)
			}
			dir := filepath.Dir(store.path)
			if err := os.Chmod(dir, 0500); err != nil {
				t.Fatal(err)
			}
			defer os.Chmod(dir, 0700)
			// The data/sidecar remain readable/writable; the failed operation is temp creation.
			if _, err := store.list(); err != nil {
				t.Fatalf("read prerequisite: %v", err)
			}
			w := authCall(h, method, "/v1/history/test-record", `{"favorite":true}`, token)
			if w.Code != 503 {
				t.Fatalf("unsaved mutation reported %d %s", w.Code, w.Body.String())
			}
			if err := os.Chmod(dir, 0700); err != nil {
				t.Fatal(err)
			}
			after, err := os.ReadFile(store.path)
			if err != nil {
				t.Fatal(err)
			}
			if string(before) != string(after) {
				t.Fatal("failed mutation changed durable state")
			}
			reopened, err := openHistory(store.path)
			if err != nil {
				t.Fatal(err)
			}
			items, err := reopened.list()
			if err != nil || len(items) != 1 || items[0].Favorite {
				t.Fatalf("failed mutation committed: %v %v", items, err)
			}
		})
	}
}

func TestHistorySlowPatchDoesNotHoldStorageOrOwnerLock(t *testing.T) {
	_, h, token, _, store := historyFixture(t)
	reader, writer := io.Pipe()
	started := make(chan struct{})
	done := make(chan struct{})
	body := &signaledHistoryBody{ReadCloser: reader, started: started}
	r := httptest.NewRequest("PATCH", "/v1/history/test-record", body)
	r.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	go func() { h.ServeHTTP(w, r); close(done) }()
	defer writer.Close()
	defer reader.Close()
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("body read not started")
	}
	progress := make(chan error, 1)
	go func() { progress <- store.append(translationRecord{ID: "concurrent-insert"}) }()
	select {
	case err := <-progress:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("slow body blocked insert")
	}
	if _, err := writer.Write([]byte(`{"favorite":true}`)); err != nil {
		t.Fatal(err)
	}
	writer.Close()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("PATCH stuck")
	}
	if w.Code != 200 {
		t.Fatalf("PATCH %d %s", w.Code, w.Body.String())
	}
	var got translationRecord
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil || !got.Favorite {
		t.Fatalf("favorite %v %v", got, err)
	}
	items, err := store.list()
	if err != nil || len(items) != 2 {
		t.Fatalf("insert lost %v %v", items, err)
	}
}

type signaledHistoryBody struct {
	io.ReadCloser
	started chan struct{}
	once    sync.Once
}

func (b *signaledHistoryBody) Read(p []byte) (int, error) {
	b.once.Do(func() { close(b.started) })
	return b.ReadCloser.Read(p)
}
