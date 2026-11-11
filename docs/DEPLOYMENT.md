# Deployment and release

## Episode state/cache release candidate — 2026-11-11

- Native: shared owner-scoped pending preparations, episode association, protected history/podcast cache, retained content during refresh/errors, no initial empty-state flash, and removal of the subscribed-podcasts section heading. Fresh translator defaults **ru→de** on iOS and web; explicit/history directions remain authoritative.
- Server: durable import identity before worker/provider admission, concurrent import coalescing, and retained historical-twin suppression without deletion. Local full Go race suite: **293 passes / 4 opt-in skips**, vet passed. Native CI rerun: **42 passed / 1 environment skip**, including the actual AppModel harness. Earlier unchanged native simulator acceptance: **21 UI tests**, full Core **56 Swift Testing + 10 XCTest**. Web: **27 Node tests** and **18 real-browser synthetic direction/history/layout checks** passed.
- Built Linux arm64 backend `sha256:cdaf691d6c1f16d5d5428f7acef6457b4b1cd5bbb8824f52d65d9c923639c73d` using the now-published `golang:1.27.4-bookworm` builder. Deployment targets **only `keinemagie`** through the established base + override. Worker image `44b2fccc4df1…`, resources, networks, mounts, and unrelated containers must remain unchanged.
- **Deployment pending tool approval** at this record: production still runs `ff3561338e27…`; public guest controls remain disabled, but the live selector is still de→ru. No new image/HTTP/retained-file verification is claimed yet. Prepared non-destructive backup/rollback helper has not executed.
- Authoritative store path verified from effective `HISTORY_PATH` and server source: `/app/data/podcasts/jobs.json`. Current snapshot **0 jobs / 1 subscription**, previous private long-release backup **2 jobs**; cause of change unknown. No records were deleted/restored/manually edited. See [read-only audit and limits](PODCAST-IDEMPOTENCY-VERIFICATION.md).

## Long-episode release — 2026-11-11

Deployed **both** existing services via the same base + durable override below; no other services changed. Production https://keinemagie.tinyserve.org is usable for explicit owner episode actions up to **3 hours / 300 MiB**, subject to transcript, processing-time and unchanged personal quota bounds. This is not a claim of three-hour continuous inference performance.

- Backend pinned image: `sha256:ff3561338e274971612df3882f7509993a7d1f3308e3a9da04ea6ce13c187957`, built from reviewed Go source with network-disabled build steps.
- Worker pinned image: `sha256:44b2fccc4df1e32c75cab89e88a0759e72534608cfde3201faf4f1e11c27bdd8`; `/app/worker.py` byte-identical to repository source (SHA256 `ee34ced0017834975d82f1dea94e8a7f4d142fea603d4d4e6e89cb21bb8f2e1b`).
- Prior actual backend: `sha256:13840f4973fc2ceff72ae481c34f952326b103460a185c4bedc484c2ee4fd1e6`; prior worker: `sha256:13d8467eb3ee0be58934ed3129370449ce8829f7a4b49b1d44bc6551663e0f11`. Both retained for rollback.
- Private pre-release override, exact prior container/image map, data hashes and 0600 data/cache tar backups: `deployment/release-20261111-long/` under the existing service directory. All non-lock auth/history/provider/podcast files remained byte-identical; 2 existing jobs, no active jobs at deployment, no artificial store changes. Existing secret volumes and all mount destinations preserved.
- Worker readback: **2 GiB memory and memory+swap (no swap)**, **512 MiB noexec tmpfs**, 2 CPUs, 64 PIDs; prior capability set and read-only/no-new-privileges/ulimits retained. Backend resources unchanged. No worker published ports, edge membership, provider or owner mounts. Internal `tinyserve_podcast_private` membership exactly backend + worker after probes exited; unrelated container IDs unchanged.
- Live authenticated real-model readiness **200** before and after worker restart; unauthenticated readiness **401**. Generated **660-second, 314572800-byte** speech/silence/bookend WAV streamed over real HTTP to the deployed worker: **200**, 3.97s, final “Bibliothek” marker recognized at **649.8–653.8s**, ordered absolute timestamps. Live cgroup peak **1133875200 bytes**, all OOM/max counters zero. One initial post-response capacity probe raced workspace cleanup; bounded retry confirmed capacity returns. This fixture is not continuous 11-minute speech or three-hour inference.
- Public certificate-validating IPv4 HTTPS `/health` **200**, `/v1/podcasts` **401**, `/v1/podcasts/subscriptions` **401**. No personal provider inference/refresh was triggered by acceptance; no paid fallback exists. Real user-episode → personal translation remains pending an explicit episode action.
- Independent review fixed upfront charging of unsent translation batches. Full remaining-plan eligibility stays under account-wide flock; only each actual/ambiguous provider attempt is durably charged. Unsent capacity releases automatically on cancel/error/crash; quota stays **100/day**, shared with text translation. Retry resumes full transcript and completed translation batches, not in-flight recognition chunks.
- Verified: Go race + vet; worker 10 Python tests; full disposable real Linux container verifier (including Go durable completion with **synthetic translation**); native CI 43 tests (one built-metadata test initially skipped, subsequently all 3 metadata tests passed against fresh built app); lifecycle 8; Swift 56 Testing + 5 XCTest; fresh app-only Release simulator build. Five-locale native limits/quota/retry help updated. GitHub publication/TestFlight are separate push-triggered gates, not evidence of production provider completion.

Rollback if health fails: restore `release-20261111-long/compose.previous.yml` as the durable override, pin its backend image to the prior actual backend ID above rather than a potentially moved tag, and apply **only** `podcast-worker keinemagie` with the same base and `--no-deps --pull never`. Preserve all volumes; do not restore old auth records over live data. Read back health, auth, resources, mounts and network membership. Rollback was prepared, not destructively exercised.

## Historical live release — 2026-11-10

Production: https://keinemagie.tinyserve.org. Existing tinyserve project `tinyserve`, backend service `keinemagie`, private recognition service `podcast-worker`. This rollout was explicitly authorized. Only these two services were started/recreated/restarted; unrelated container IDs, including tunnel/proxy, were verified unchanged.

- Rebuilt `keinemagie:translator` with Go **1.27.3**: `sha256:1d3aa9bc2a5b77f017a06bd827742d83cb39e9252d3bae9417a6b94fa3a8bf48` (Linux arm64).
- Isolated worker image: `sha256:13d8467eb3ee0be58934ed3129370449ce8829f7a4b49b1d44bc6551663e0f11`.
- Previous backend image retained: `sha256:eea8c49aad8ec769b54a4b5738bee3da05d839b69e62bf8ccd5b6503ea27c6dc`.
- Existing external volumes retained: `keinemagie-data`, `keinemagie-cache`, `keinemagie-provider-key`, `keinemagie-apple-key`. Every preexisting non-lock data file was byte-identical after deployment; observed counts remained **1 user, 2 sessions, 4 provider-related files**. No owner identifiers or credential values were printed. This establishes persistence, not provider validity or real inference.
- Before rollout, private backups of all four volumes, prior Compose override and image ID were saved under `deployment/release-20261110/` within the existing service directory. Backup tar files are 0600.

## Durable local Compose workaround

The existing tinyserve service registry still refers to `keinemagie:local`; normal `tinyserve deploy` does **not** preserve this manual override/private worker configuration. Do not use it blindly. This is the established local-image Compose workaround, **not automatic registry-to-host deployment**. GitHub still publishes `ghcr.io/ptmt/diktat-server`; publication does not deploy this host. Local Apple Silicon image and CI registry artifact are distinct artifacts.

Always merge these exact files, targeting only intended services:

```sh
BASE='/Users/tinyserve/Library/Application Support/tinyserve/generated/.staging-20261108-144857/docker-compose.yml'
OVERRIDE='/Users/tinyserve/Library/Application Support/tinyserve/services/keinemagie/deployment/compose.translator.yml'
docker-compose -p tinyserve -f "$BASE" -f "$OVERRIDE" up -d --no-deps --pull never podcast-worker keinemagie
```

The standalone `docker-compose` binary is installed; this host does not have the `docker compose` plugin. Render config programmatically and print only these services' nonsecret fields: the shared base contains unrelated service secrets. Do not print the whole base/config or environment values.

`tinyserve_podcast_private` is internal and its exact live membership was verified as backend + worker only. Backend additionally retains `tinyserve_edge`; worker has no edge membership, published ports, provider/account mounts, or Traefik route (`traefik.enable=false`). Worker read-only root, no-new-privileges, drop ALL/add SETUID/SETGID/CHOWN/KILL, 2 CPUs, 1100 MiB memory+swap limit, 64 PIDs and bounded noexec tmpfs were read back from Docker.

## Worker authentication

One cryptographically random 32-byte secret, encoded as lowercase hex, was provisioned outside Git into two separate host 0600 files under `deployment/podcast-secrets/` (directory 0700). Secure stdin tar copy populated two separate Linux named volumes, enforcing ownership despite Docker/macOS sharing differences:

- `keinemagie-podcast-worker-auth`: root-owned 0600 `/run/secrets/podcast_token`, read-only worker mount.
- `keinemagie-podcast-backend-auth`: UID/GID 65532, 0600 `/run/keinemagie-worker/token`, read-only backend mount.

The worker volume contains only its worker credential; backend volume only its backend copy. Never mount either copy into decoder processes or put the value in Compose, command arguments, environment or logs. Backend config contains only `PODCAST_WORKER_URL=http://podcast-worker:8091` and the token-file path. Public provider fallback remains disabled.

Authenticated readiness requires **both** Bearer auth and `X-Podcast-Version: 1`; omitting the latter returns a protocol error, not failed model readiness. Use an ephemeral curl client on the private network with the backend credential volume mounted read-only and UID 65532; read the token inside that client and pipe a header through curl's stdin config (never expose it as a process argument). A transient third network member is expected only during that probe; verify final exact membership afterward.

## Verified gates

- Full Go race suite and `go vet ./...` passed.
- Node **22.22.3** web suite: **22 passed**.
- Native Python CI: **39 passed**, including actual built app metadata; lifecycle harness: **8 passed**.
- Swift package: **46 Swift Testing + 3 XCTest**, all passed.
- Fresh standard app-only Release simulator build succeeded; deep strict codesign verification succeeded. Standard project keeps only existing Apple sign-in entitlement, no App Group or share-extension requirement.
- Worker unit tests: **2 passed**. Disposable Linux fixture verified real German speech recognition, auth/oversize/manifest rejection, contention/disconnect cancellation, blocked internet, decoder secret isolation, read-only app, no public ports, and Go durable completion using **synthetic provider translation**.
- Live worker authenticated readiness returned version 1, ready true, capacity 1, both before and after an actual worker restart. Invalid auth returned **401**.
- Public TLS `/health`: **200**. Guest `/v1/podcasts`, `/v1/podcasts/subscriptions`, `/v1/web/session`: **401**. Guest legacy `/v1/translations`: **503** with shared provider disabled; not an authorized feature success.
- Real production browser showed four navigation links and truly disabled guest input/style/translate controls, plus in-place Apple sign-in guidance.

No real podcast or paid provider inference was performed. Real owner-authorized episode → recognition → translation remains pending a concrete user-supplied episode. Feed refresh is manual and subscription never auto-enqueues processing. Dictation/coach remain honest unavailable destinations. Share-extension source is an opt-in overlay only: **not shipped**, pending App Group-capable app + extension profiles and a reviewed signing pipeline. Do not modify Apple portal provisioning automatically.

## Non-destructive rollback procedure (documented, not executed)

If backend health regresses, preserve all persistent volumes and current auth/provider files. Create a temporary rollback override selecting the retained prior backend image above, clear `PODCAST_WORKER_URL` and `PODCAST_WORKER_TOKEN_FILE`, and apply it **last** after the same base + durable override, targeting `keinemagie` with `--no-deps --pull never`. Keep the private worker untouched unless independently implicated. Verify public health, auth boundary, original mount identity and data counts. Do not restore an old auth/history backup over live records merely to roll back a binary. The saved pre-release override can aid reconstruction; do not blindly retag or deploy the whole stack. Actual destructive rollback was not tested.

## Native release path

Pushes to main touching `native/**` trigger `.github/workflows/ios-testflight.yml`: validate, app-only archive/export/upload. Workflow status, successful upload and user-confirmed installation are separate gates. Exact current run URLs and observed upload result are recorded in release verification/reporting, never inferred from the local simulator build.
