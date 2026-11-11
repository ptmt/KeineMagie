package main

import (
	"errors"
	"os"
	"strconv"
	"time"
)

const (
	podcastMaxBytes             int64 = 300 << 20
	podcastMaxDuration                = 10800
	podcastMaxSegments                = 3600
	podcastMaxCharacters              = 216000
	podcastMaxSegmentCharacters       = 8000
	podcastMaxResponseBytes           = 4 << 20
	podcastProcessingTimeout          = 120 * time.Minute
	podcastWorkerTimeout              = 90 * time.Minute
	podcastLeaseDuration              = 125 * time.Minute
	podcastStoreMaxBytes              = 128 << 20
)

type podcastLimits struct {
	bytes    int64
	duration int
}

// Administrators can lower limits, never lift the tested hard ceilings.
func configuredPodcastLimits() (podcastLimits, error) {
	limits := podcastLimits{podcastMaxBytes, podcastMaxDuration}
	if raw := os.Getenv("PODCAST_MAX_BYTES"); raw != "" {
		n, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || n < 1 || n > podcastMaxBytes {
			return podcastLimits{}, errors.New("invalid podcast limits")
		}
		limits.bytes = n
	}
	if raw := os.Getenv("PODCAST_MAX_DURATION_SECONDS"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 || n > podcastMaxDuration {
			return podcastLimits{}, errors.New("invalid podcast limits")
		}
		limits.duration = n
	}
	return limits, nil
}
