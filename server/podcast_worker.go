package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
)

type podcastService struct {
	remote                             *podcastRemote
	running                            atomic.Bool
	cfg                                *serverConfig
	store                              *podcastStore
	whisper, ffmpeg, ffprobe, modelDir string
	sourceFetcher                      *podcastFetcher                             // nil uses hardened production defaults
	fetchAudio                         func(context.Context, string, string) error // nil uses hardened public fetcher
}

func newPodcasts(cfg *serverConfig) (*podcastService, error) {
	s, e := openPodcastStore(filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json"))
	if e != nil {
		return nil, e
	}
	p := &podcastService{cfg: cfg, store: s}
	// Recognition is isolated from this sole auth/provider authority. There is
	// deliberately no host-executable fallback, including on invalid config.
	if endpoint := os.Getenv("PODCAST_WORKER_URL"); endpoint != "" {
		p.remote, e = newPodcastRemote(endpoint, os.Getenv("PODCAST_WORKER_TOKEN_FILE"))
	}
	if p.remote == nil {
		return p, nil
	}
	go p.run(context.Background())
	return p, nil
}
func (p *podcastService) ready() error {
	if p.remote == nil || !p.running.Load() {
		return errors.New("private podcast worker unavailable")
	}
	return p.remote.ready(context.Background())
}

// Legacy local recognition is retained solely for the opt-in Mac fixture test;
// production configuration never executes decoders in the backend process.
func (p *podcastService) localToolsReady() error {
	for _, bin := range []string{p.whisper, p.ffmpeg, p.ffprobe} {
		if !filepath.IsAbs(bin) {
			return errors.New("podcast worker needs absolute Whisper, ffmpeg and ffprobe executable paths")
		}
		info, e := os.Stat(bin)
		if e != nil || !info.Mode().IsRegular() || info.Mode()&0111 == 0 {
			return errors.New("podcast executable unavailable")
		}
	}
	if !filepath.IsAbs(p.modelDir) {
		return errors.New("podcast worker needs absolute PODCAST_MODEL_DIR with preinstalled base.pt")
	}
	info, e := os.Stat(filepath.Join(p.modelDir, "base.pt"))
	if e != nil || !info.Mode().IsRegular() {
		return errors.New("podcast Whisper base.pt model missing; install before enabling worker")
	}
	return nil
}
func (p *podcastService) run(ctx context.Context) {
	// One worker globally across processes sharing this durable store. An OS crash
	// releases the lock. Stale claims recover after the bounded lease deadline.
	lock, e := os.OpenFile(p.store.lock.path+".worker", os.O_CREATE|os.O_RDWR, 0600)
	if e != nil {
		return
	}
	defer lock.Close()
	if syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB) != nil {
		return
	}
	defer syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)
	p.running.Store(true)
	defer p.running.Store(false)
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if p.remote == nil || p.remote.ready(ctx) != nil {
				continue
			}
			j, e := p.store.claim(time.Now())
			if e == nil && j.ID != "" {
				p.process(ctx, j)
			}
		}
	}
}
func (p *podcastService) process(parent context.Context, job podcastJob) {
	ctx, cancel := context.WithTimeout(parent, 40*time.Minute)
	defer cancel()
	// Cancellation is durable and observed during fetch/recognition, not just before publishing.
	owner, claim := job.Owner, job.Claim // immutable goroutine capture
	done := make(chan struct{})
	defer close(done)
	go func() {
		tick := time.NewTicker(time.Second)
		defer tick.Stop()
		for {
			select {
			case <-done:
				return
			case <-ctx.Done():
				return
			case <-tick.C:
				jobs, e := p.store.list(owner)
				active := false
				if e == nil {
					for _, j := range jobs {
						if j.Claim == claim && podcastActive(j.State) {
							active = true
						}
					}
				}
				if !active {
					cancel()
					return
				}
			}
		}
	}()
	e := p.prepare(ctx, &job)
	if e != nil {
		job.State = "failed"
		job.Error = e.Error()
		if ctx.Err() != nil {
			job.Error = "worker canceled or exceeded 40 minute processing limit"
		}
	} else {
		job.State = "completed"
		job.Progress = 100
		job.Error = ""
	}
	_ = p.store.update(job)
}
func (p *podcastService) prepare(ctx context.Context, job *podcastJob) error {
	dir, e := os.MkdirTemp(filepath.Dir(p.store.lock.path), "audio-*")
	if e != nil {
		return errors.New("audio workspace unavailable")
	}
	defer os.RemoveAll(dir)
	audio := filepath.Join(dir, "source.audio")
	fetch := p.fetchAudio
	if fetch == nil {
		fetch = (podcastFetcher{}).fetch
	}
	if e = fetch(ctx, job.URL, audio); e != nil {
		return e
	}
	job.State = "transcribing"
	job.Progress = 20
	if e = p.store.update(*job); e != nil {
		return e
	}
	segments, e := p.transcribe(ctx, audio, dir, job.SourceLanguage)
	if e != nil {
		return e
	}
	job.Segments = segments
	job.State = "translating"
	job.Progress = 50
	if e = p.store.update(*job); e != nil {
		return e
	}
	for i := range job.Segments {
		if ctx.Err() != nil {
			return errors.New("worker canceled")
		}
		if e = p.store.update(*job); e != nil {
			return e
		}
		translated, e := p.translateSegment(ctx, job.Owner, translationInput{Text: job.Segments[i].Text, SourceLanguage: job.SourceLanguage, TargetLanguage: job.TargetLanguage})
		if e != nil {
			return e
		}
		job.Segments[i].Translation = translated
		job.Progress = 50 + (i+1)*49/len(job.Segments)
		if e = p.store.update(*job); e != nil {
			return e
		}
	}
	return nil
}

// Commands receive fixed arguments and local paths only, never user URL/text.
// ffmpeg/ffprobe only read file or pipe, so embedded playlists cannot fetch URLs.
func (p *podcastService) transcribe(ctx context.Context, audio, dir, language string) ([]podcastSegment, error) {
	if p.remote != nil {
		return p.remote.transcribe(ctx, audio, language)
	}
	if os.Getenv("PODCAST_REAL_TEST") != "1" {
		return nil, errors.New("private transcription worker unavailable")
	}
	probe := exec.CommandContext(ctx, p.ffprobe, "-v", "error", "-protocol_whitelist", "file,pipe", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", audio)
	probe.Stdout = &limitedPodcastBuffer{max: 1024}
	probe.Stderr = io.Discard
	if probe.Run() != nil {
		return nil, errors.New("invalid or unsupported audio")
	}
	duration, e := strconv.ParseFloat(strings.TrimSpace(probe.Stdout.(*limitedPodcastBuffer).text()), 64)
	if e != nil || math.IsNaN(duration) || math.IsInf(duration, 0) || duration <= 0 || duration > 600 {
		return nil, errors.New("audio duration must be at most 10 minutes")
	}
	wav := filepath.Join(dir, "speech.wav")
	ff := exec.CommandContext(ctx, p.ffmpeg, "-nostdin", "-v", "error", "-protocol_whitelist", "file,pipe", "-i", audio, "-t", "601", "-vn", "-ac", "1", "-ar", "16000", "-f", "wav", wav)
	ff.Stdout = io.Discard
	ff.Stderr = io.Discard
	if ff.Run() != nil {
		return nil, errors.New("audio normalization failed")
	}
	stat, e := os.Stat(wav)
	if e != nil || stat.Size() > 20<<20 {
		return nil, errors.New("decoded audio exceeds limit")
	}
	command := exec.CommandContext(ctx, p.whisper, wav, "--model", "base", "--model_dir", p.modelDir, "--device", "cpu", "--fp16", "False", "--language", language, "--task", "transcribe", "--output_format", "json", "--output_dir", dir, "--verbose", "False", "--threads", "2")
	command.Stdout = io.Discard
	command.Stderr = io.Discard
	// No provider secrets in the child environment; fixed PATH supports Whisper's ffmpeg lookup.
	command.Env = []string{"PATH=" + filepath.Dir(p.ffmpeg) + ":/usr/bin:/bin", "HOME=" + dir, "PYTHONUNBUFFERED=1"}
	if command.Run() != nil {
		return nil, errors.New("local Whisper transcription failed")
	}
	file, e := os.Open(filepath.Join(dir, "speech.json"))
	if e != nil {
		return nil, errors.New("Whisper produced no transcript")
	}
	defer file.Close()
	b, e := io.ReadAll(io.LimitReader(file, (1<<20)+1))
	if e != nil || len(b) > 1<<20 {
		return nil, errors.New("transcript exceeds limit")
	}
	var output struct {
		Segments []podcastSegment `json:"segments"`
	}
	if json.Unmarshal(b, &output) != nil {
		return nil, errors.New("invalid timestamped transcript")
	}
	total := 0
	previous := 0.0
	segments := []podcastSegment{}
	for _, s := range output.Segments {
		s.Text = strings.TrimSpace(s.Text)
		s.Translation = ""
		if s.Text == "" {
			continue
		}
		if math.IsNaN(s.Start) || math.IsNaN(s.End) || math.IsInf(s.Start, 0) || math.IsInf(s.End, 0) || s.Start < previous || s.End <= s.Start || s.End > 601 {
			return nil, errors.New("invalid transcript timestamps")
		}
		previous = s.Start
		total += runeCount(s.Text)
		segments = append(segments, s)
	}
	if len(segments) == 0 || len(segments) > 120 || total > 8000 {
		return nil, errors.New("transcript must contain speech, at most 120 segments and 8000 characters")
	}
	return segments, nil
}

type limitedPodcastBuffer struct {
	data []byte
	max  int
}

func (b *limitedPodcastBuffer) Write(p []byte) (int, error) {
	if len(b.data)+len(p) > b.max {
		return 0, errors.New("output too large")
	}
	b.data = append(b.data, p...)
	return len(p), nil
}
func (b *limitedPodcastBuffer) text() string { return string(b.data) }
func (p *podcastService) translateSegment(ctx context.Context, owner string, input translationInput) (string, error) {
	provider := p.cfg.provider
	release, e := provider.beginTranslation(owner, time.Now())
	if e != nil {
		return "", errors.New("personal translation quota reached; retry later")
	}
	defer release()
	unlock, e := provider.lockOwner(ctx, owner)
	if e != nil {
		return "", errors.New("translation canceled")
	}
	defer unlock()
	c, e := provider.access(ctx, owner)
	if e != nil {
		return "", errors.New("connect your personal ChatGPT account before retrying")
	}
	models, e := provider.models(ctx, c.AccessToken)
	if e != nil {
		return "", errors.New("personal model catalog unavailable")
	}
	model := chooseModel(models)
	if model == "" {
		return "", errors.New("no personal text model available")
	}
	text, e := provider.translate(ctx, c.AccessToken, model, input)
	if e != nil {
		return "", errors.New("personal translation failed or incomplete")
	}
	return text, nil
}
