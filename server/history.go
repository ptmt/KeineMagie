package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"syscall"
)

// A sidecar flock coordinates cooperating server processes; the mutex also
// serializes goroutines. Never lock the data inode, which rename replaces.
type historyStore struct {
	path string
	mu   sync.Mutex
}

func openHistory(path string) (*historyStore, error) {
	s := &historyStore{path: path}
	err := s.locked(func() error { _, err := s.read(); return err })
	return s, err
}
func (s *historyStore) locked(fn func() error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := os.MkdirAll(filepath.Dir(s.path), 0700); err != nil {
		return err
	}
	f, err := os.OpenFile(s.path+".lock", os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer f.Close()
	if err = f.Chmod(0600); err != nil {
		return err
	}
	if err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		return err
	}
	defer syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
	return fn()
}
func (s *historyStore) read() ([]translationRecord, error) {
	data, err := os.ReadFile(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return []translationRecord{}, nil
	}
	if err != nil {
		return nil, err
	}
	if err = os.Chmod(s.path, 0600); err != nil {
		return nil, err
	}
	var items []translationRecord
	if err = json.Unmarshal(data, &items); err != nil {
		return nil, err
	}
	if items == nil {
		items = []translationRecord{}
	}
	return items, nil
}
func (s *historyStore) list() ([]translationRecord, error) {
	var items []translationRecord
	err := s.locked(func() error { var err error; items, err = s.read(); return err })
	sort.SliceStable(items, func(i, j int) bool { return items[i].CreatedAt.After(items[j].CreatedAt) })
	if len(items) > 100 {
		items = items[:100]
	}
	return items, err
}
func (s *historyStore) append(record translationRecord) error {
	return s.locked(func() error {
		items, err := s.read()
		if err != nil {
			return err
		}
		items = append(items, record)
		data, err := json.Marshal(items)
		if err != nil {
			return err
		}
		dir := filepath.Dir(s.path)
		f, err := os.CreateTemp(dir, ".history-*")
		if err != nil {
			return err
		}
		defer os.Remove(f.Name())
		defer f.Close()
		if _, err = f.Write(data); err != nil {
			return err
		}
		if err = f.Sync(); err != nil {
			return err
		}
		if err = f.Close(); err != nil {
			return err
		}
		if err = os.Rename(f.Name(), s.path); err != nil {
			return err
		}
		d, err := os.Open(dir)
		if err != nil {
			return err
		}
		defer d.Close()
		return d.Sync()
	})
}
