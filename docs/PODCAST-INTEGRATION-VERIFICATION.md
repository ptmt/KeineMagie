# Podcast HTML/RSS integration verification

Verified locally on 2026-11-10. No commit, push, deployment or provider inference was performed.

## Integrated changes

- Added all eight source/feed UI keys from `PODCAST-SOURCE-HANDOFF.md` to the app string catalog, with German, English, Russian, Spanish and French translations. The discovery notice explicitly requires manual feed refresh and explicit preparation before transcription/translation.
- Added a discoverable localization contract for those eight keys and five distinct translations per key. Observed it fail for missing keys before adding the catalog entries.
- Upgraded the server Docker builder from Go 1.22 to the published official `golang:1.27.3-bookworm` image. Preserved `go 1.23.0` as the module minimum and `golang.org/x/net v0.43.0`; no dependency downgrade.

## Go version selection and image artifact

Official [Go release history](https://go.dev/doc/devel/release) lists Go 1.27.4, released 2026-11-10. The [downloads JSON](https://go.dev/dl/?mode=json) returned 1.27.1 during this verification, so it was not treated as conclusive. The [Docker official image manifest source](https://raw.githubusercontent.com/docker-library/official-images/master/library/golang) listed 1.27.3; actual registry lookup of `golang:1.27.4-bookworm` returned `no such manifest`, while 1.27.3-bookworm resolved and pulled successfully. Upgrade to 1.27.4 when its official image becomes available; do not claim this builder contains the 1.27.4 security fixes.

Actual build, with public dependency download enabled and no secret arguments or mounted credentials:

```sh
docker build --network=default -f server/Dockerfile -t keinemagie:podcast-integration .
```

- Builder pull digest: `sha256:dc0963f32053e4bc451d24d87e3892d42d01021b61f093e98eb95c0352bb84b0`.
- Built image: `sha256:5c04b823d0b8918313b3c7c7e44f0a5ecf894fdea361043d42915cebb0b239e4`, Linux arm64, `nonroot:nonroot`.
- Extracted real binary build information confirms `go1.27.3`, `CGO_ENABLED=0`, `golang.org/x/net v0.43.0`, and JWT v5.3.0.
- Ephemeral image smoke test used `--network=none` and a curl container sharing its network namespace: `/health` returned HTTP 200 and real status JSON; unauthenticated `/v1/podcasts/subscriptions` returned HTTP 401. The test container was removed afterward. No host port or production storage was used.
- Docker Buildx is not installed locally: `--progress=plain` was rejected. The supported legacy-builder invocation above completed all 20 steps, including `go mod download` and `go build`. CI already installs Buildx and consumes the same Dockerfile; no workflow change was necessary.

This is a local image of the working-tree snapshot at build time, not a deployment or a promise that subsequent concurrent worker/web edits are included. Rebuild the final integrated tree before shipping.

## Native and server gates

- Full native Python CI: **39 tests, all passed**, with `KM_BUILT_APP_PLIST` pointing to the actual built Release simulator app (no skipped metadata test). Its executable AppModel lifecycle harness additionally passed **8 Swift Testing tests** using synthetic transport.
- Full Swift package suite: **46 Swift Testing tests + 3 XCTest tests**, all passed.
- Standard app-only Release iOS Simulator build succeeded with ad-hoc signing. `codesign --verify --deep --strict` succeeded.
- Compiled app string tables match all **40** new translated values (eight keys × five languages). All five nested SwiftPM locale tables are present, each with 20 entries. Resource verification used `plutil` because copied SwiftPM `.strings` resources need not be binary/XML plists.
- Full Go `go test -race ./...` passed.
- Build warning: App Intents metadata extraction skipped because this app has no AppIntents.framework dependency.
- This gate did not install/launch the new app or perform a new real-account consent, physical-device share, speech-recognition, or paid-provider test. Previous handoff evidence is separate.

Local evidence is under `/Users/tinyserve/.hermes/cache/scratch/`: `km-podcast-docker-build.log`, `km-podcast-native-ci-built.log`, `km-podcast-swift-tests.log`, `km-podcast-xcode-build.log`, `km-podcast-go-race.log`, and `km-podcast-native-build/Build/Products/Release-iphonesimulator/KeineMagie.app`.

## Independent source/feed review

Reviewed source/feed fetch, parser, API handlers, store and worker cancellation/quota boundaries without editing the podcast server files.

- **SSRF:** URL syntax excludes userinfo, query capabilities, fragments and nonstandard ports. Every redirect is validated, every connection rejects mixed private/public DNS answers and dials a validated IP directly. Environment proxies are disabled. HTML alternate/audio references reuse the policy; there is no recursive extractor or credential forwarding. XML has no external entity resolution, rejects directives, and has byte/depth/token/episode bounds.
- **Authentication:** handlers resolve the existing authenticated owner before discovery/subscription actions; browser mutations require exact Origin and session-bound CSRF. Subscription list, lookup, refresh and delete scope to owner. Live image smoke verification confirms unauthenticated rejection.
- **Deduplication:** feed parse and refresh merge reject duplicate GUID/Atom IDs and enclosure URLs. Store locking preserves subscription identity across repeated subscribe; unsubscribe fences late refresh writes. Deduplication is metadata-level only: explicitly preparing an episode twice can create two independently budgeted jobs; no exactly-once ingestion guarantee is claimed.
- **Cancellation:** discover/fetch requests propagate context and deadlines; refresh checks cancellation before persistence. Worker cancellation uses durable state polling and claim fencing. The full race suite covers existing claim-fencing behavior. A cancellation arriving after the last context check but during the short synchronous store write is not a transactional rollback guarantee.
- **Quotas:** subscription caps (10/owner, 100/global), 50 episodes, 2 MiB documents, shared six/minute source refresh throttle, and the existing ingestion/translation budgets are enforced. Discovery never automatically reserves AI quota or enqueues a job. Source network concurrency has a rate limit and deadlines, not a separate global in-flight semaphore.

No concrete source/feed security blocker was identified in this review. Nonblocking follow-ups: strengthen direct tests for refresh cancellation while a response is stalled, simultaneous subscribe deduplication, and hitting source-specific quota limits. Current tests cover canceled-before-fetch, mixed DNS, private redirect, XML bounds, owner isolation, no-AI discovery, repeated subscription identity, merge dedup and late-refresh-after-delete.

**Subscription refresh remains manual.** There is no scheduler, background feed polling, automatic backfill or automatic feed-to-AI processing. Foreground job progress polling does not discover new feed episodes.
