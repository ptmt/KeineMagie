package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"time"
)

type authSession struct {
	Kind    string    `json:"kind,omitempty"`
	UserID  string    `json:"user_id"`
	Expires time.Time `json:"expires_at"`
}
type authData struct {
	Users    map[string]string      `json:"users"`
	Sessions map[string]authSession `json:"sessions"`
}
type authStore struct{ lock *historyStore }

func openAuthStore(path string) (*authStore, error) {
	s := &authStore{lock: &historyStore{path: path}}
	err := s.lock.locked(func() error { _, err := s.read(); return err })
	return s, err
}
func (s *authStore) read() (authData, error) {
	d := authData{Users: map[string]string{}, Sessions: map[string]authSession{}}
	b, err := os.ReadFile(s.lock.path)
	if errors.Is(err, os.ErrNotExist) {
		return d, nil
	}
	if err != nil {
		return d, err
	}
	if err = os.Chmod(s.lock.path, 0600); err != nil {
		return d, err
	}
	if err = json.Unmarshal(b, &d); err != nil {
		return d, err
	}
	if d.Users == nil || d.Sessions == nil {
		return d, errors.New("invalid auth store")
	}
	return d, nil
}
func (s *authStore) write(d authData) error {
	b, err := json.Marshal(d)
	if err != nil {
		return err
	}
	dir := filepath.Dir(s.lock.path)
	f, err := os.CreateTemp(dir, ".auth-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	defer f.Close()
	if _, err = f.Write(b); err != nil {
		return err
	}
	if err = f.Sync(); err != nil {
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	if err = os.Rename(f.Name(), s.lock.path); err != nil {
		return err
	}
	p, err := os.Open(dir)
	if err != nil {
		return err
	}
	defer p.Close()
	return p.Sync()
}
func sessionHash(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
func (s *authStore) create(subject string, now time.Time) (string, authSession, error) {
	token := randomAuthToken()
	var session authSession
	err := s.lock.locked(func() error {
		d, err := s.read()
		if err != nil {
			return err
		}
		key := "https://appleid.apple.com\x00" + subject
		id := d.Users[key]
		if id == "" {
			id = randomAuthToken()
			d.Users[key] = id
		}
		for k, v := range d.Sessions {
			if !now.Before(v.Expires) {
				delete(d.Sessions, k)
			}
		}
		session = authSession{UserID: id, Expires: now.Add(30 * 24 * time.Hour)}
		d.Sessions[sessionHash(token)] = session
		return s.write(d)
	})
	return token, session, err
}
func (s *authStore) lookup(token string, now time.Time) (authSession, error) {
	var session authSession
	err := s.lock.locked(func() error {
		d, err := s.read()
		if err != nil {
			return err
		}
		session = d.Sessions[sessionHash(token)]
		if session.UserID == "" || !now.Before(session.Expires) {
			return errors.New("invalid session")
		}
		return nil
	})
	return session, err
}

func (s *authStore) revoke(token string, now time.Time) error {
	return s.lock.locked(func() error {
		d, err := s.read()
		if err != nil {
			return err
		}
		key := sessionHash(token)
		v := d.Sessions[key]
		if v.UserID == "" || !now.Before(v.Expires) {
			return errors.New("invalid session")
		}
		delete(d.Sessions, key)
		return s.write(d)
	})
}
