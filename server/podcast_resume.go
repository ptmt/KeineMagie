package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"time"
)

// Stored only in the private store, never serialized by the owner API.
type podcastResume struct {
	Digest   string  `json:"sha256"`
	Bytes    int64   `json:"bytes"`
	Config   string  `json:"config"`
	End      float64 `json:"end_seconds"`
	Complete bool    `json:"complete"`
}

// Only the exclusive global worker-flock holder may recover. Possessing that
// lock proves no previous process is still working, regardless of lease age.
func (s *podcastStore) recoverInterrupted(now time.Time) error {
	return s.lock.locked(func() error {
		d, e := s.read()
		if e != nil {
			return e
		}
		changed := false
		for i := range d.Jobs {
			j := &d.Jobs[i]
			if podcastActive(j.State) && j.State != "queued" {
				j.State = "queued"
				j.Claim = ""
				j.Lease = time.Time{}
				j.ResumePending = true
				j.UpdatedAt = now.UTC()
				changed = true
			}
		}
		if changed {
			return s.write(d)
		}
		return nil
	})
}

func podcastSyncDir(dir string) error {
	f, e := os.Open(dir)
	if e != nil {
		return e
	}
	defer f.Close()
	return f.Sync()
}
func (s *podcastStore) mediaRoot() string { return filepath.Join(filepath.Dir(s.lock.path), "media") }

// Hash the opaque ID instead of trusting it as a path component (including old stores).
func (s *podcastStore) mediaPath(j podcastJob) string {
	return filepath.Join(s.mediaRoot(), sessionHash(j.Owner+"\x00"+j.ID)+".audio")
}
func podcastMediaHash(path string, max int64) (string, int64, error) {
	st, e := os.Lstat(path)
	if e != nil {
		return "", 0, e
	}
	if !st.Mode().IsRegular() || st.Size() <= 0 || st.Size() > max {
		return "", 0, errors.New("invalid staged media")
	}
	f, e := os.Open(path)
	if e != nil {
		return "", 0, e
	}
	defer f.Close()
	h := sha256.New()
	n, e := io.Copy(h, io.LimitReader(f, max+1))
	if e != nil || n != st.Size() {
		return "", 0, errors.New("invalid staged media")
	}
	return hex.EncodeToString(h.Sum(nil)), n, nil
}
func podcastDiskCap() (int64, error) {
	n := int64(2 << 30)
	if raw := os.Getenv("PODCAST_MEDIA_MAX_BYTES"); raw != "" {
		v, e := strconv.ParseInt(raw, 10, 64)
		if e != nil || v < 1 || v > 2<<30 {
			return 0, errors.New("invalid podcast media disk cap")
		}
		n = v
	}
	return n, nil
}
func podcastResumeTTL() (time.Duration, error) {
	n := int64(7 * 24 * 3600)
	if raw := os.Getenv("PODCAST_RESUME_TTL_SECONDS"); raw != "" {
		v, e := strconv.ParseInt(raw, 10, 64)
		if e != nil || v < 1 || v > 30*24*3600 {
			return 0, errors.New("invalid podcast resume TTL")
		}
		n = v
	}
	return time.Duration(n) * time.Second, nil
}

// Runs under global worker flock; store lock also serializes owner deletion.
func (s *podcastStore) cleanupMedia(now time.Time) error {
	return s.lock.locked(func() error {
		d, e := s.read()
		if e != nil {
			return e
		}
		ttl, e := podcastResumeTTL()
		if e != nil {
			return e
		}
		keep := map[string]bool{}
		for _, j := range d.Jobs {
			if j.State != "completed" && (podcastActive(j.State) || now.Sub(j.UpdatedAt) < ttl) {
				keep[filepath.Base(s.mediaPath(storedPodcast(j)))] = true
			}
		}
		entries, e := os.ReadDir(s.mediaRoot())
		if os.IsNotExist(e) {
			return nil
		}
		if e != nil {
			return e
		}
		for _, entry := range entries {
			if !keep[entry.Name()] {
				if e = os.RemoveAll(filepath.Join(s.mediaRoot(), entry.Name())); e != nil {
					return e
				}
			}
		}
		return podcastSyncDir(s.mediaRoot())
	})
}
func (p *podcastService) stageMedia(ctx context.Context, j *podcastJob) (string, error) {
	limits, e := configuredPodcastLimits()
	if e != nil {
		return "", e
	}
	cap, e := podcastDiskCap()
	if e != nil {
		return "", e
	}
	root := p.store.mediaRoot()
	if e = os.MkdirAll(root, 0700); e != nil {
		return "", e
	}
	if e = p.store.cleanupMedia(time.Now()); e != nil {
		return "", e
	}
	path := p.store.mediaPath(*j)
	digest, n, e := podcastMediaHash(path, limits.bytes)
	if e == nil {
		if j.Resume != nil && (j.Resume.Digest != digest || j.Resume.Bytes != n || j.Resume.Config != "base:v1:"+j.SourceLanguage) {
			return "", errors.New("staged media identity mismatch")
		}
	} else {
		if !os.IsNotExist(e) {
			return "", e
		}
		entries, e := os.ReadDir(root)
		if e != nil {
			return "", e
		}
		used := int64(0)
		for _, entry := range entries {
			st, e := entry.Info()
			if e != nil {
				return "", e
			}
			// Never follow links or count targets outside the private media root.
			if st.Mode()&os.ModeSymlink != 0 {
				continue
			}
			if !st.Mode().IsRegular() {
				return "", errors.New("invalid media staging entry")
			}
			used += st.Size()
		}
		// Reserve the maximum download before opening the byte stream. Single global
		// worker means no concurrent reservation can overcommit this bounded volume.
		if used+limits.bytes > cap {
			return "", errors.New("podcast media disk cap reached; delete retained episodes or retry after expiry")
		}
		part := path + ".partial"
		_ = os.Remove(part)
		fetch := p.fetchAudio
		if fetch == nil {
			fetch = (podcastFetcher{}).fetch
		}
		if e = fetch(ctx, j.URL, part); e != nil {
			_ = os.Remove(part)
			return "", e
		}
		digest, n, e = podcastMediaHash(part, limits.bytes)
		if e != nil {
			_ = os.Remove(part)
			return "", e
		}
		if j.Resume != nil && (j.Resume.Digest != digest || j.Resume.Bytes != n || j.Resume.Config != "base:v1:"+j.SourceLanguage) {
			_ = os.Remove(part)
			return "", errors.New("source media changed; retained recognition cannot be resumed")
		}
		f, e := os.OpenFile(part, os.O_RDWR, 0600)
		if e != nil {
			return "", e
		}
		e = f.Sync()
		_ = f.Close()
		if e != nil {
			return "", e
		}
		if e = os.Rename(part, path); e != nil {
			return "", e
		}
		if e = podcastSyncDir(root); e != nil {
			return "", e
		}
	}
	if j.Resume == nil {
		j.Resume = &podcastResume{Digest: digest, Bytes: n, Config: "base:v1:" + j.SourceLanguage}
	}
	if e = p.store.update(*j); e != nil {
		return "", e
	}
	return path, nil
}

func (p *podcastService) prepareResumable(ctx context.Context, j *podcastJob) error {
	if len(j.Segments) > 0 && (j.Resume == nil || j.Resume.Complete) {
		return p.translatePodcast(ctx, j)
	}
	path, e := p.stageMedia(ctx, j)
	if e != nil {
		return e
	}
	j.State = "transcribing"
	j.Progress = 20
	if e = p.store.update(*j); e != nil {
		return e
	}
	if p.remote == nil {
		return fmt.Errorf("private transcription worker unavailable")
	}
	if e = p.remote.transcribeResumable(ctx, path, j, func() error { return p.store.update(*j) }); e != nil {
		return e
	}
	j.State = "translating"
	j.Progress = 50
	if e = p.store.update(*j); e != nil {
		return e
	}
	return p.translatePodcast(ctx, j)
}
