# Isolated podcast recognition worker

The existing Linux backend remains the only identity/provider authority and durable job writer. This worker accepts **audio bytes only** plus fixed DE/RU language and protocol headers. It receives no owner tokens, URLs, provider keys, account mounts, commands, or model selection. Translation remains in the backend under the job owner's existing provider path.

## Reproduce locally (no production changes)

From repository root on this Mac:

```sh
mkdir -p server/podcast-worker/models
cp /Users/tinyserve/.cache/whisper/base.pt server/podcast-worker/models/base.pt
docker build -t keinemagie-podcast-worker:candidate server/podcast-worker
python3 -m unittest discover -s server/podcast-worker -p test_worker.py
python3 server/podcast-worker/verify_container.py
(cd server && go test -race ./... && go vet ./...)
```

Model bytes are ignored by Git, copied into the Linux image and SHA256-verified during build. Do not mount Mac executables or Homebrew Python into Linux. Python dependency versions are pinned; Debian package repositories still resolve their current security revisions at build time. The fixture uses Mac `say` only to generate audio, then real **Linux** ffprobe/ffmpeg/Whisper; it creates/removes its own internal Docker network, temporary secret volume, containers, and disposable Go test stores. No public ports or production mounts are used. Its printed transcript is synthetic test speech, not user content.

## Deployment handoff — existing live deployment

`compose.example.yml` is a merge snippet, not a replacement backend definition. Retain every existing backend mount, auth/provider configuration, image release path, edge network and origin. Add an **internal** network shared only by backend and worker. The worker must have no edge network, published port, reverse-proxy route, Docker socket or provider/auth mounts. Do not launch another complete backend. The candidate Go client must be included in an approved backend image rollout before imports work; building the worker alone does not modify the running backend.

Generate one 32-byte cryptographically random secret encoded as 64 lowercase hex characters. Store identical contents in **separate** 0600 files: worker copy root-owned (UID 0), backend copy owned by its runtime UID (currently distroless 65532). Only mount each individual file, read-only. Never place secrets in environment values, command arguments, source control or logs. Compose file-secret permission remapping is not portable for host bind files, so provision ownership explicitly and verify inside the target container before rollout. The fixture uses a Linux named volume to enforce ownership despite Docker/Mac file-sharing differences.

Configure existing backend:

```
PODCAST_WORKER_URL=http://podcast-worker:8091
PODCAST_WORKER_TOKEN_FILE=/app/podcast-worker-token
```

HTTP is permitted **only on the isolated Docker network**. Use HTTPS/mTLS if crossing any other network. The backend transport disables proxies/redirects and pins a DNS-validated private/loopback address; it is separate from public source SSRF transport. Endpoint is administrator configuration, never request input. Invalid/missing endpoint/token fails ingestion closed with the library still usable. Old `PODCAST_LOCAL_WORKER` executable configuration no longer enables production recognition. No full-backend Mac migration is supported.

Review rendered merged Compose with `docker compose config` before any approved rollout. Back up existing persistent records under owner control; preserve release/rollback mechanism. Never run this snippet directly to replace the live service.

## Protocol and containment

- Bearer constant-time auth **before body read**, fixed protocol version 1.
- `GET /internal/podcast/ready`: authenticated version/readiness/capacity; listener starts only after ffmpeg/ffprobe execution and cached model import/load/real silent inference smoke. Busy returns 503. Backend checks runner lock ownership plus live readiness and does not claim while unavailable; failed claims stay durable/retryable.
- `POST /internal/podcast/transcribe`: exact `Content-Length` (no chunking), octet-stream, `X-Podcast-Language: de|ru`, `X-Podcast-Version: 1`; maximum 300 MiB, maximum decoded duration 10800s (3 hours). Single admitted job; 429 on contention, at most four connection handler threads, bounded backlog/header/socket/upload timeouts. Upload total <=600s, probe <=20s, and one total upload/probe/recognition deadline <=5400s (90 minutes). `PODCAST_WORKER_TIMEOUT_SECONDS` may only reduce the total deadline; invalid values fail startup. `PODCAST_MAX_BYTES` and `PODCAST_MAX_DURATION_SECONDS` may only lower their hard ceilings and are passed explicitly to restricted children.
- Fixed signature-selected `wav,aiff,flac,ogg,mp3,mov` demuxers and `file,pipe` protocols; manifests rejected before decoding. This intentionally supports fewer containers than arbitrary ffmpeg auto-detection. Decode 16 kHz mono PCM through one continuous ffmpeg pipe, consume disjoint <=600s windows sequentially, and reject decoded sample counts above 3h even if metadata lies. No full-episode WAV or full waveform allocation: only the encoded source is on tmpfs, plus one <=19.2 MB PCM chunk and bounded stage output (24 MiB per-child file quota). Pipe backpressure bounds decoder buffering. Exact digital-silence bookends are trimmed without removing quiet nonzero speech; sample offsets restore global timestamps. Whisper model loads once per request and runs each nonempty chunk sequentially. MP4 is admitted via MOV demuxer; malformed or unsupported parser inputs fail generically.
- Entire process group is killed on timeout or client disconnect, including grandchildren; Go context cancellation closes the RPC. Privilege dropping is a fresh fixed Python stage process, not unsafe `preexec_fn` in a threaded server.
- Root supervisor reads the 0600 token; **every decoder/ML child is UID/GID 1001 with no supplementary groups**, fixed reduced environment and closed inherited FDs. No token environment or provider credentials. Token file is unreadable by that UID (fixture verifies).
- Read-only root, bounded 512 MiB noexec tmpfs, no core dumps, CPU/file/FD limits, Compose 2 CPUs/2 GiB/no swap/64 PIDs, dropped capabilities except supervisor setuid/setgid/chown/kill, no-new-privileges. Model/libraries are public read-only image data, workspace is ephemeral. No worker runtime internet egress on internal network (fixture verifies direct internet TCP failure); this is not a claim of per-process seccomp network isolation from its private backend peer. No generic command API exists.
- Response <=4 MiB, <=3600 nonempty segments, <=216000 Unicode characters total and <=8000 per segment, finite nonoverlapping timestamps ending <=10800s. Default synchronous response retains version 1 and `segments`, with additive `language` (legacy JSON still requires nonempty speech). Opt in with `Accept: application/x-ndjson` and optional `X-Resume-Offset: 0|600|...|10800`: after the original full encoded upload is probed, each fully recognized window emits a flushed checkpoint, including silence; completion is emitted only after clean decoder/producer exit. HTTP/1.1 response uses `Connection: close`, no Content-Length, EOF framing; only the `complete` event signifies success. Post-header failure emits fixed `recognition_failed`, never exception details. Absolute timestamps/index/endpoints follow `RESUME-CONTRACT.md`. Invalid offset headers fail before upload; offsets beyond original duration fail 422 before streaming headers. Equal exact duration completes without recognition. Input `-ss` with ffmpeg accurate seeking skips prior compressed windows, output `-ss 0` retains the remaining timeline without double trimming. One remaining-input PCM pipe avoids decoding/allocating all prior PCM. Streaming keeps one chunk, not the full transcript, with cumulative caps. Backend stores original encoded media and fsynced checkpoints; worker requires no persistent audio volume. Job IDs/digests are not interpreted as paths. Final partial checkpoint is the backend's durable completed endpoint; a nonmultiple duration is not a valid resume header. Disjoint decoded windows prevent pipeline overlap/duplicate windows; timestamps are clipped to their actual window. This is not a guarantee against recognition errors or a word split exactly at a 600s boundary. Backend independently validates and strips supplied translations. Durable owner claim fences still prevent stale completion after cancel/recovery. Request logs and decoder stderr are suppressed; client-facing errors are fixed generic strings.

The 512 MiB tmpfs is an intentional bounded in-memory upload workspace: a 300 MiB source plus <=4 MiB stage JSON fits without ever writing decoded PCM. Tmpfs memory is charged to the 2 GiB cgroup; do not deploy the old 160 MiB/1100 MiB settings. No dedicated persistent volume or unbounded host disk is required. This supersedes the dedicated-disk suggestion in the coordination contract for this implementation.

## Verified versus still required

Fixture generates an actual 660-second German speech/silence/German-final-marker WAV, pads it with a valid RIFF JUNK chunk to exactly 300 MiB, streams it over HTTP, and checks a recognized final marker after 600s and global ordered timestamps. It records cgroup memory peak, OOM counters, CPU stats, image SHA and elapsed time. This exercises long decoding/chunk transitions and maximum upload size, not 11 minutes of continuous speech or 3 hours of model inference.

Fixture gates: authenticated readiness; missing auth 401; oversized upload 413; nested-manifest 422; real German speech recognition; contention 429; disconnect releases capacity; real deadline kills child and grandchild process group; no internet route; no published ports; child cannot read secret; read-only application; no auth/transcript logs; real Go Linux client -> durable claim -> real worker -> **synthetic** owner-provider Responses translation -> completed. Source URL fetching is intentionally fixture-injected in this container gate; existing hardened-fetch tests cover its independent boundary. This is not a real-account inference claim.

Backend and pinned worker were deployed 2026-11-11 via the existing local Compose override. Live authenticated readiness before/after restart and generated 660-second / 300 MiB HTTP recognition passed; account/provider/job files stayed byte-identical and final private membership is backend + worker only. See `../../docs/DEPLOYMENT.md`. Real owner-authorized episode completion, continuous multi-hour inference, and destructive rollback remain untested.
