package main

import (
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"sort"
	"time"
)

type podcastSegment struct {
	Start       float64 `json:"start"`
	End         float64 `json:"end"`
	Text        string  `json:"text"`
	Translation string  `json:"translation,omitempty"`
}
type podcastJob struct {
	ID             string           `json:"id"`
	Owner          string           `json:"-"`
	URL            string           `json:"url"`
	FeedID         string           `json:"feed_id,omitempty"`
	EpisodeID      string           `json:"episode_id,omitempty"`
	Title          string           `json:"title,omitempty"`
	SourceURL      string           `json:"source_url,omitempty"`
	SourceLanguage string           `json:"source_language"`
	TargetLanguage string           `json:"target_language"`
	State          string           `json:"state"`
	Progress       int              `json:"progress"`
	Error          string           `json:"error,omitempty"`
	ErrorCode      string           `json:"error_code,omitempty"`
	CreatedAt      time.Time        `json:"created_at"`
	UpdatedAt      time.Time        `json:"updated_at"`
	Attempts       int              `json:"attempts"`
	Segments       []podcastSegment `json:"segments"`
	Lease          time.Time        `json:"-"`
	Claim          string           `json:"-"`
	Resume         *podcastResume   `json:"-"`
	ResumePending  bool             `json:"-"`
}
type podcastStoredJob struct {
	podcastJob
	Owner         string         `json:"owner"`
	Lease         time.Time      `json:"lease"`
	Claim         string         `json:"claim"`
	Resume        *podcastResume `json:"resume,omitempty"`
	ResumePending bool           `json:"resume_pending,omitempty"`
}
type podcastBudget struct {
	Day      string `json:"day"`
	Attempts int    `json:"attempts"`
}
type podcastData struct {
	Subscriptions []podcastStoredSubscription `json:"subscriptions,omitempty"`
	Jobs          []podcastStoredJob          `json:"jobs"`
	Budgets       map[string]podcastBudget    `json:"budgets"`
}
type podcastStore struct{ lock *historyStore }

var errPodcastNotFound = errors.New("podcast not found")
var errPodcastLimit = errors.New("podcast limit reached")

func openPodcastStore(path string) (*podcastStore, error) {
	s := &podcastStore{lock: &historyStore{path: path}}
	e := s.lock.locked(func() error { _, e := s.read(); return e })
	return s, e
}
func (s *podcastStore) read() (podcastData, error) {
	d := podcastData{Jobs: []podcastStoredJob{}, Budgets: map[string]podcastBudget{}}
	f, e := os.Open(s.lock.path)
	if errors.Is(e, os.ErrNotExist) {
		return d, nil
	}
	if e != nil {
		return d, e
	}
	defer f.Close()
	info, e := f.Stat()
	if e != nil {
		return d, e
	}
	if info.Size() > podcastStoreMaxBytes {
		return d, errors.New("podcast store exceeds storage limit; delete retained episodes administratively")
	}
	b, e := io.ReadAll(io.LimitReader(f, podcastStoreMaxBytes+1))
	if e != nil {
		return d, e
	}
	if len(b) > podcastStoreMaxBytes {
		return d, errors.New("podcast store exceeds storage limit")
	}
	if e = os.Chmod(s.lock.path, 0600); e != nil {
		return d, e
	}
	e = json.Unmarshal(b, &d)
	if e == nil && (d.Jobs == nil || d.Budgets == nil) {
		e = errors.New("invalid podcast store")
	}
	return d, e
}
func (s *podcastStore) write(d podcastData) error {
	b, e := json.Marshal(d)
	if e != nil {
		return e
	}
	if len(b) > podcastStoreMaxBytes {
		return errors.New("podcast store exceeds storage limit")
	}
	dir := filepath.Dir(s.lock.path)
	f, e := os.CreateTemp(dir, ".podcasts-*")
	if e != nil {
		return e
	}
	defer os.Remove(f.Name())
	defer f.Close()
	if _, e = f.Write(b); e != nil {
		return e
	}
	if e = f.Sync(); e != nil {
		return e
	}
	if e = f.Close(); e != nil {
		return e
	}
	if e = os.Rename(f.Name(), s.lock.path); e != nil {
		return e
	}
	p, e := os.Open(dir)
	if e != nil {
		return e
	}
	defer p.Close()
	return p.Sync()
}
func podcastActive(state string) bool {
	return state == "queued" || state == "fetching" || state == "transcribing" || state == "translating"
}
func podcastReserve(d *podcastData, owner string, now time.Time) error {
	if e := podcastCheckAdmission(*d, owner, now); e != nil {
		return e
	}
	key := sessionHash(owner)
	q := d.Budgets[key]
	day := now.UTC().Format("2006-01-02")
	if q.Day != day {
		q = podcastBudget{Day: day}
	}
	if q.Attempts >= 4 {
		return errPodcastLimit
	}
	q.Attempts++
	d.Budgets[key] = q
	return nil
}
func (s *podcastStore) create(owner, raw, source string, now time.Time) (podcastJob, error) {
	return s.createEpisode(owner, raw, source, "", "", "", now)
}
func (s *podcastStore) createEpisode(owner, raw, source, feedID, episodeID, sourceURL string, now time.Time) (podcastJob, error) {
	return s.episode(owner, raw, source, feedID, episodeID, sourceURL, now, false, nil)
}

// Lookup and admission share one identity path. Admission runs only for a genuinely
// new job, under the durable store lock, before reserving any budget.
func (s *podcastStore) episode(owner, raw, source, feedID, episodeID, sourceURL string, now time.Time, lookupOnly bool, admit func() error) (podcastJob, error) {
	var job podcastJob
	e := s.lock.locked(func() error {
		d, e := s.read()
		if e != nil {
			return e
		}
		title := ""
		if feedID != "" || episodeID != "" {
			found := false
			for _, sub := range d.Subscriptions {
				if sub.Owner != owner || sub.ID != feedID {
					continue
				}
				for _, ep := range sub.Episodes {
					if ep.ID == episodeID {
						raw, title, found = ep.URL, ep.Title, true
						break
					}
				}
			}
			if !found {
				return errPodcastNotFound
			}
		} else {
			// Associate legacy enclosure imports only when unambiguous. Different
			// GUIDs may legitimately share audio and must remain distinct.
			matches := 0
			for _, sub := range d.Subscriptions {
				if sub.Owner == owner {
					for _, ep := range sub.Episodes {
						if ep.URL == raw {
							matches++
							feedID, episodeID, title = sub.ID, ep.ID, ep.Title
						}
					}
				}
			}
			if matches != 1 {
				feedID, episodeID, title = "", "", ""
			}
		}
		candidate := podcastJob{Owner: owner, URL: raw, SourceLanguage: source, FeedID: feedID, EpisodeID: episodeID}
		best := -1
		for i, existing := range d.Jobs {
			sameSource := sourceURL != "" && sourceURL != raw && existing.Owner == owner && existing.SourceLanguage == source && existing.FeedID == "" && existing.SourceURL == "" && existing.URL == sourceURL
			if (podcastSameEpisode(storedPodcast(existing), candidate) || sameSource) && (best < 0 || podcastIdentityRank(existing.State) > podcastIdentityRank(d.Jobs[best].State)) {
				best = i
			}
		}
		if best >= 0 {
			j := &d.Jobs[best]
			changed := false
			if j.FeedID == "" && j.SourceURL == "" && sourceURL != "" && sourceURL != raw && j.URL == sourceURL {
				// Only the exact same supplied page proves this historical alias.
				// Do not rewrite a live worker's input or infer aliases by title.
				if j.Claim == "" {
					j.URL, j.SourceURL = raw, sourceURL
					changed = true
				}
			}
			if j.SourceURL == "" && sourceURL != "" && sourceURL != raw && feedID == "" && j.URL == raw {
				j.SourceURL = sourceURL
				changed = true
			}
			if j.FeedID == "" && feedID != "" {
				j.FeedID, j.EpisodeID, j.Title = feedID, episodeID, title
				changed = true
			}
			if changed {
				if e := s.write(d); e != nil {
					return e
				}
			}
			job = storedPodcast(*j)
			return nil
		}
		if lookupOnly {
			return nil
		}
		if e = podcastCheckAdmission(d, owner, now); e != nil {
			return e
		}
		if admit != nil {
			if e := admit(); e != nil {
				return e
			}
		}
		if e = podcastReserve(&d, owner, now); e != nil {
			return e
		}
		target := "ru"
		if source == "ru" {
			target = "de"
		}
		job = podcastJob{ID: randomAuthToken(), Owner: owner, URL: raw, FeedID: feedID, EpisodeID: episodeID, Title: title, SourceURL: sourceURL, SourceLanguage: source, TargetLanguage: target, State: "queued", CreatedAt: now.UTC(), UpdatedAt: now.UTC(), Segments: []podcastSegment{}}
		d.Jobs = append(d.Jobs, podcastStoredJob{podcastJob: job, Owner: owner})
		return s.write(d)
	})
	return job, e
}
func storedPodcast(j podcastStoredJob) podcastJob {
	v := j.podcastJob
	v.Owner = j.Owner
	v.Lease = j.Lease
	v.Claim = j.Claim
	v.Resume = j.Resume
	v.ResumePending = j.ResumePending
	return v
}
func (s *podcastStore) list(owner string) ([]podcastJob, error) {
	jobs, _, err := s.listWithLimits(owner, time.Now())
	return jobs, err
}
func (s *podcastStore) listWithLimits(owner string, now time.Time) ([]podcastJob, podcastOwnerLimits, error) {
	jobs := []podcastJob{}
	var limits podcastOwnerLimits
	e := s.lock.locked(func() error {
		d, e := s.read()
		if e != nil {
			return e
		}
		for _, j := range d.Jobs {
			if j.Owner == owner {
				jobs = append(jobs, storedPodcast(j))
			}
		}
		limits = podcastLimitsFor(d, owner, now)
		return nil
	})
	sort.Slice(jobs, func(i, j int) bool { return jobs[i].CreatedAt.After(jobs[j].CreatedAt) })
	return jobs, limits, e
}
func (s *podcastStore) mutate(owner, id, action string, now time.Time) (podcastJob, error) {
	var job podcastJob
	e := s.lock.locked(func() error {
		d, e := s.read()
		if e != nil {
			return e
		}
		for i := range d.Jobs {
			j := &d.Jobs[i]
			if j.Owner != owner || j.ID != id {
				continue
			}
			switch action {
			case "retry":
				for k, other := range d.Jobs {
					if k != i && podcastSameEpisode(storedPodcast(other), storedPodcast(*j)) && (podcastActive(other.State) || other.State == "completed") {
						job = storedPodcast(other)
						return nil
					}
				}
				if (j.State != "failed" && j.State != "canceled") || j.Attempts >= 3 {
					return errors.New("only failed jobs with fewer than three attempts can retry")
				}
				// Exclude this retained item from the capacity count while reserving a retry.
				copyData := podcastData{Jobs: append([]podcastStoredJob{}, d.Jobs[:i]...), Budgets: d.Budgets}
				copyData.Jobs = append(copyData.Jobs, d.Jobs[i+1:]...)
				// Retrying an admitted identity must not spend (or require) another
				// daily admission; capacity still applies.
				copyData.Budgets = map[string]podcastBudget{}
				if e = podcastCheckAdmission(copyData, owner, now); e != nil {
					return e
				}
				j.State = "queued"
				j.Error = ""
				j.ErrorCode = ""
				j.Progress = 0
				j.Claim = ""
				j.Lease = time.Time{}
			// Preserve validated transcript and completed translations for retry.
			case "cancel":
				if !podcastActive(j.State) {
					return errors.New("job is not active")
				}
				j.State = "canceled"
				j.Claim = ""
				j.Lease = time.Time{}
			case "delete":
				if podcastActive(j.State) {
					return errors.New("cancel active jobs before deleting")
				}
				job = storedPodcast(*j)
				d.Jobs = append(d.Jobs[:i], d.Jobs[i+1:]...)
				if e = s.write(d); e != nil {
					return e
				}
				_ = os.Remove(s.mediaPath(job))
				_ = os.Remove(s.mediaPath(job) + ".partial")
				if _, e := os.Stat(s.mediaRoot()); e == nil {
					return podcastSyncDir(s.mediaRoot())
				}
				return nil
			default:
				return errors.New("invalid action")
			}
			j.UpdatedAt = now.UTC()
			job = storedPodcast(*j)
			return s.write(d)
		}
		return errPodcastNotFound
	})
	return job, e
}
func (s *podcastStore) claim(now time.Time) (podcastJob, error) {
	var job podcastJob
	e := s.lock.locked(func() error {
		d, e := s.read()
		if e != nil {
			return e
		}
		changed := false
		for i := range d.Jobs {
			j := &d.Jobs[i]
			if j.State != "queued" && !(podcastActive(j.State) && now.After(j.Lease)) {
				continue
			}
			canonical := true
			for k, other := range d.Jobs {
				if k == i || !podcastSameEpisode(storedPodcast(other), storedPodcast(*j)) {
					continue
				}
				if other.State == "completed" || podcastIdentityRank(other.State) > podcastIdentityRank(j.State) || (podcastIdentityRank(other.State) == podcastIdentityRank(j.State) && k < i) {
					canonical = false
					break
				}
			}
			if !canonical {
				j.State = "failed"
				j.Error = "duplicate episode retained; use its existing preparation (no worker attempt spent)"
				j.Claim, j.Lease = "", time.Time{}
				j.UpdatedAt = now.UTC()
				changed = true
				continue
			}
			// Settle historical queued twins in the same write as the claim, so a
			// fast canonical failure cannot cause the next poll to run a twin.
			for k := range d.Jobs {
				other := &d.Jobs[k]
				if k != i && other.State == "queued" && podcastSameEpisode(storedPodcast(*other), storedPodcast(*j)) {
					other.State = "failed"
					other.Error = "duplicate episode retained; use its existing preparation (no worker attempt spent)"
					other.Claim, other.Lease = "", time.Time{}
					other.UpdatedAt = now.UTC()
					changed = true
				}
			}
			if j.Attempts >= 3 && !j.ResumePending {
				j.State = "failed"
				j.Error = "worker interrupted; retry limit reached"
				j.Claim = ""
				changed = true
				continue
			}
			if !j.ResumePending {
				j.Attempts++
			}
			j.ResumePending = false
			j.State = "fetching"
			j.Progress = 5
			j.Error = ""
			j.ErrorCode = ""
			if len(j.Segments) != 0 && (j.Resume == nil || j.Resume.Complete) {
				j.State = "translating"
				j.Progress = 50
			}
			j.Claim = randomAuthToken()
			j.Lease = now.Add(podcastLeaseDuration)
			j.UpdatedAt = now.UTC()
			job = storedPodcast(*j)
			return s.write(d)
		}
		if changed {
			return s.write(d)
		}
		return nil
	})
	return job, e
}

// Claim fencing prevents a canceled/retried/recovered worker from publishing results.
func (s *podcastStore) update(job podcastJob) error {
	return s.lock.locked(func() error {
		d, e := s.read()
		if e != nil {
			return e
		}
		for i := range d.Jobs {
			j := &d.Jobs[i]
			if j.ID == job.ID && j.Owner == job.Owner && j.Claim == job.Claim && job.Claim != "" && podcastActive(j.State) {
				job.UpdatedAt = time.Now().UTC()
				d.Jobs[i] = podcastStoredJob{podcastJob: job, Owner: job.Owner, Lease: job.Lease, Claim: job.Claim, Resume: job.Resume, ResumePending: job.ResumePending}
				return s.write(d)
			}
		}
		return errors.New("job canceled or claim expired")
	})
}
