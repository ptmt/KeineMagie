# Durable podcast resume (backend)

The backend owns encoded-media staging and recognition/translation checkpoints. Deploy backend and the Python NDJSON worker together; `podcast-worker/RESUME-CONTRACT.md` is the opt-in wire contract. Legacy JSON worker calls remain available to old clients, but durable backend jobs require NDJSON support (fail closed, no silent restart-from-zero fallback).

## Persistent volume and bounds

Mount the directory containing `HISTORY_PATH` as the existing private persistent application volume. Jobs are in `podcasts/jobs.json`; original encoded audio is in sibling `podcasts/media/`. Do not mount this media directory on tmpfs or an ephemeral container layer. No worker cache volume is needed. Only fixed SHA256-derived owner/job names are used; source URLs, worker identifiers, titles and request paths never become filesystem names. Media content is rehashed by streaming and bound to stored byte count, SHA256 and recognition config (`base:v1:<language>`).

Downloads stream to `.audio.partial`, are fsynced, atomically renamed, and the containing directory is fsynced before the private job checkpoint is committed. A crash before the checkpoint can reuse a complete renamed original. A partial download is never recognized and is removed/refetched under the exclusive worker lock. Existing `audio-*` scratch cleanup does not remove durable media.

- `PODCAST_MAX_BYTES`: encoded per-file limit, default/hard ceiling 300 MiB.
- `PODCAST_MEDIA_MAX_BYTES`: staging capacity, default/hard ceiling 2 GiB, may be lowered. Admission reserves the configured maximum single-file bytes against retained bytes before starting download; this deliberately rejects some small downloads conservatively rather than overcommitting. One global worker flock serializes all staging writers. Existing over-limit volumes block further staging; retained originals are not silently evicted.
- `PODCAST_RESUME_TTL_SECONDS`: failed/canceled original retention, default seven days, maximum thirty days; may be lowered to one second. Active originals do not expire. Completed/deleted originals are removed; crash-orphan and expired original cleanup runs at worker startup/queue ticks. Jobs/transcripts remain governed by existing retained-job limits.
- Duration remains at most 10800 seconds, recognition chunks at most 600 seconds. Transcript/store ceilings are unchanged.

A canceled job keeps completed chunks/media until TTL to permit explicit Retry. Delete removes its staged original. If expired original media is fetched again, the digest must match before using old recognition; changed publisher bytes fail rather than mixing transcripts. Removing a job then importing anew is the way to intentionally recognize changed source bytes.

## Crash semantics

An exclusive cross-process OS worker flock proves no other backend worker owns the store. Immediately after acquiring it, startup clears interrupted claims and requeues them; it does not wait for the old 125-minute lease. Every result/checkpoint write is fenced by the current opaque claim and owner. Cancel, retry, recovery and deletion invalidate old claims; stale requests cannot publish. Restart resumes the same admitted identity and attempt; explicit retries retain their existing three-attempt policy but do not charge another daily podcast admission.

One full upload produces flushed NDJSON chunk checkpoints. Backend validates absolute chunk indices, bounded/nonoverlapping global timestamps, language and completion, then atomically fsyncs accumulated transcript plus cursor before consuming the next event. Incomplete recognition is never translated. After death, only the uncheckpointed chunk is recognized again; the full original is uploaded once at resume offset. If a short final checkpoint was persisted but its complete event was lost, only that short final window repeats and replaces its previous segments. No partial results are duplicated. Graceful parent-context cancellation requeues rather than recording user cancellation; abrupt SIGTERM/SIGKILL is recovered on next startup.

Translation saves each validated finished batch before another provider request and skips saved translations on resume. Exactly-once external inference cannot be guaranteed: death after upstream completion but before durable save can repeat that single in-flight batch. Quota consumption is durable immediately before each send; death between charge and send can conservatively charge one attempt. Unsent remainder is not charged; cross-process reservation flocks release on death. No claim is made that an external provider transaction is atomic with local storage.

## Independent integration verification

The independent review reran the full Go race suite (**329 passed / 5 opt-in skips**) and vet, and all **17 Python tests**. Added regressions cover final partial checkpoint EOF/replay at 660, no auto-execution or mutation of failed jobs, symbolic-link-safe staging accounting, and fixed sanitized provider failure codes (`error_code`) for refusal, timeout, incomplete stream and invalid mapping. No automatic provider retries were introduced; each failed batch remains failed pending explicit owner Retry.

`TestPodcastRealContainerSIGKILLResume`, enabled with `PODCAST_REAL_RESUME=1` plus `PODCAST_REAL_AUDIO`, `PODCAST_REAL_TOKEN`, `PODCAST_REAL_WORKER`, now verifies the actual Go orchestrator against the unmodified pinned Linux worker. The generated 660-second German speech/silence bookends use real Whisper; only the strict Responses SSE translation server is synthetic. Both backend SIGKILL cuts passed: after durable 600 and after durable final 660 **before complete**. Each restarted immediately, uploaded at offset **600** (never invalid 660), downloaded once, kept attempt one, preserved both real speech markers and completed one synthetic translation batch. No partial ASR was translated. Observed cgroup peak **781471744 bytes**, all max/OOM counters zero. This test's disposable worker uses a temporary loopback-only published port so the host Go test can connect; the separate Python verifier covers internal-only/no-port worker isolation.

## Verification

```
cd server
go test ./... -count=1
go test -race ./... -run 'TestPodcast(SIGKILLRecovery|NDJSON|RestartImmediately|ProcessStop|ExpiredStage|MediaRetention)' -count=1
```

`TestPodcastSIGKILLRecovery` launches actual Go subprocesses, kills them during download, after checkpoint zero, and while translation batch two is in flight, then immediately starts another process against the same persistent files. It checks only completed media is used, offset 600 resumes without redownload, finished translation batch one is not repeated, attempts remain one, and completed media is removed. Worker responses and provider Responses SSE are explicit synthetic wire fixtures, not paid inference or speech-recognition evidence. Real 660-second speech/bookend recognition needs the separate Python worker integration fixture and must not be inferred from these wire tests.

No production data, deployment, commits or provider calls are required by these tests.
