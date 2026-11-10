# Isolated podcast recognition worker (candidate, not deployed)

The existing Linux backend remains the only identity/provider authority and durable job writer. This worker accepts **audio bytes only** plus fixed DE/RU language and protocol headers. It receives no owner tokens, URLs, provider keys, account mounts, commands, or model selection. Translation remains in the backend under the job owner's existing provider path.

## Reproduce locally (no production changes)

From repository root on this Mac:

```sh
mkdir -p server/podcast-worker/models
cp /Users/tinyserve/.cache/whisper/base.pt server/podcast-worker/models/base.pt
docker build -t keinemagie-podcast-worker:candidate server/podcast-worker
python3 server/podcast-worker/verify_container.py
(cd server && go test -race ./... && go vet ./...)
```

Model bytes are ignored by Git, copied into the Linux image and SHA256-verified during build. Do not mount Mac executables or Homebrew Python into Linux. Python dependency versions are pinned; Debian package repositories still resolve their current security revisions at build time. The fixture uses Mac `say` only to generate audio, then real **Linux** ffprobe/ffmpeg/Whisper; it creates/removes its own internal Docker network, temporary secret volume, containers, and disposable Go test stores. No public ports or production mounts are used. Its printed transcript is synthetic test speech, not user content.

## Deployment handoff — approval still required

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
- `POST /internal/podcast/transcribe`: exact `Content-Length` (no chunking), octet-stream, `X-Podcast-Language: de|ru`, `X-Podcast-Version: 1`; maximum 40 MiB. Single admitted job; 429 on contention, at most four connection handler threads, bounded backlog/header/socket/upload timeouts. Upload total 120s, probe 20s, normalization 45s, recognition 1800s.
- Fixed signature-selected `wav,aiff,flac,ogg,mp3,mov` demuxers and `file,pipe` protocols; manifests rejected before decoding. This intentionally supports fewer containers than arbitrary ffmpeg auto-detection. Decode 16 kHz mono, at most 600s and 24 MiB file quota. MP4 is admitted via MOV demuxer; malformed or unsupported parser inputs fail generically.
- Entire process group is killed on timeout or client disconnect, including grandchildren; Go context cancellation closes the RPC. Privilege dropping is a fresh fixed Python stage process, not unsafe `preexec_fn` in a threaded server.
- Root supervisor reads the 0600 token; **every decoder/ML child is UID/GID 1001 with no supplementary groups**, fixed reduced environment and closed inherited FDs. No token environment or provider credentials. Token file is unreadable by that UID (fixture verifies).
- Read-only root, bounded 160 MiB noexec tmpfs, no core dumps, CPU/file/FD limits, Compose 2 CPUs/1100 MiB/no swap/64 PIDs, dropped capabilities except supervisor setuid/setgid/chown/kill, no-new-privileges. Model/libraries are public read-only image data, workspace is ephemeral. No worker runtime internet egress on internal network (fixture verifies direct internet TCP failure); this is not a claim of per-process seccomp network isolation from its private backend peer. No generic command API exists.
- Response <=1 MiB, 1–120 nonempty segments, <=8000 Unicode characters, finite nonoverlapping timestamps ending <=600s. Backend independently validates and strips supplied translations. Durable owner claim fences still prevent stale completion after cancel/recovery. Request logs and decoder stderr are suppressed; client-facing errors are fixed generic strings.

## Verified versus still required

Fixture gates: authenticated readiness; missing auth 401; oversized upload 413; nested-manifest 422; real German speech recognition; contention 429; disconnect releases capacity; no internet route; no published ports; child cannot read secret; read-only application; real Go Linux client -> durable claim -> real worker -> **synthetic** owner-provider Responses translation -> completed. Source URL fetching is intentionally fixture-injected in this container gate; existing hardened-fetch tests cover its independent boundary. This is not a real-account inference claim.

Still required before production acceptance: approved backend/worker image rollout through established release path, protected secret provisioning, live account/provider persistence check, authorized real-account podcast completion, deployment restart/recovery/rollback and private-network membership inspection. No production configuration, routing, container, account record, commit or push was changed by this work.
