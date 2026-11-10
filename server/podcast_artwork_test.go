package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"hash/crc32"
	"image"
	"image/jpeg"
	"image/png"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"
)

func TestPodcastArtworkOwnerProxyAndBounds(t *testing.T) {
	var imageBytes bytes.Buffer
	png.Encode(&imageBytes, image.NewRGBA(image.Rect(0, 0, 4, 4)))
	var jpegBytes bytes.Buffer
	jpeg.Encode(&jpegBytes, image.NewRGBA(image.Rect(0, 0, 4, 4)), nil)
	largePNG := func(width, height uint32) []byte {
		b := append([]byte(nil), imageBytes.Bytes()...)
		binary.BigEndian.PutUint32(b[16:20], width)
		binary.BigEndian.PutUint32(b[20:24], height)
		binary.BigEndian.PutUint32(b[29:33], crc32.ChecksumIEEE(b[12:29]))
		return b
	}
	for _, tc := range []struct {
		mime string
		body []byte
		ok   bool
	}{
		{"image/png", imageBytes.Bytes(), true},
		{"image/jpeg", jpegBytes.Bytes(), true},
		{"image/png", jpegBytes.Bytes(), false},
		{"image/jpeg", imageBytes.Bytes(), false},
		{"image/png", largePNG(4097, 1), false},
		{"image/png", largePNG(4096, 4096), false},
		{"image/svg+xml", []byte(`<svg/>`), false},
		{"image/png", []byte(`<html/>`), false},
		{"image/png", make([]byte, (2<<20)+1), false},
	} {
		f := podcastFixtureFetcher(t, func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", tc.mime)
			w.Write(tc.body)
		})
		store, _ := openPodcastStore(filepath.Join(t.TempDir(), "jobs.json"))
		sub, err := store.saveSubscription("owner", "", podcastDiscovery{URL: "http://fixture.example/feed", ArtworkURL: "http://fixture.example/image?v=5"}, time.Now())
		if err != nil {
			t.Fatal(err)
		}
		p := podcastService{store: store, sourceFetcher: &f}
		w := httptest.NewRecorder()
		p.handleArtwork(w, httptest.NewRequest("GET", "/", nil).WithContext(context.Background()), sub)
		if (w.Code == 200) != tc.ok {
			t.Fatalf("mime=%s status=%d", tc.mime, w.Code)
		}
		if _, err := store.subscription("other", sub.ID); err != errPodcastNotFound {
			t.Fatal("owner isolation")
		}
	}
}
