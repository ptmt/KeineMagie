package main

import (
	"context"
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"
)

func TestPodcastStandbyAcquiresWorkerAfterOldProcessExits(t *testing.T) {
	s, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
	lock, e := os.OpenFile(s.lock.path+".worker", os.O_CREATE|os.O_RDWR, 0600)
	if e != nil {
		t.Fatal(e)
	}
	defer lock.Close()
	if e = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); e != nil {
		t.Fatal(e)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	p := &podcastService{store: s}
	done := make(chan struct{})
	go func() { p.run(ctx); close(done) }()
	select {
	case <-done:
		t.Fatal("standby gave up permanently while prior process held worker lock")
	case <-time.After(100 * time.Millisecond):
	}
	_ = syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if p.running.Load() {
			cancel()
			<-done
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("standby never took worker lock")
}
