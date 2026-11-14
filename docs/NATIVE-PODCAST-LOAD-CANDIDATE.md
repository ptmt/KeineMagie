# Native podcast load fix — independent review and release

Base: fresh origin/main `5b871f109034c31eaa6dd0a0d919f8bda5780305`. Isolated worktree `/Users/tinyserve/Projects/KeineMagie-podcast-load`, branch `fix/native-podcast-load`. Main/Diktat worktree untouched.

## Confirmed causal defect

`server/podcast_feed.go:46` deliberately sets each linked preparation's `Segments = nil`. Go `podcastJob` serializes this as `"segments":null`. Swift synthesized `PodcastJob` decoding required `[PodcastSegment]`: a single linked preparation therefore rejects the ENTIRE subscriptions response at `items[0].episodes[0].preparation.segments`. Library response retains full segments and decodes independently. This exactly explains the screenshot's missing feed plus retained Ready job.

Second confirmed mismatch: server serializes job metadata as `title`; native used only `episode_title`. This discards a real known title and falls back to MP3 filename. Current candidate reads server `title`, supports old cached `episode_title`, and uses associated episode metadata before filename fallback.

Shared-pattern warning for parent/Coach investigator: valid Go nil collections vs strict Swift nonoptional collection decoding can produce HTTP-200 UI failures. This is proven for Podcasts, NOT yet claimed as Coach's cause. New/empty synthetic fixtures that always use `[]` conceal this defect.

## Bounded production evidence, read-only

Running backend image: `sha256:6b79445bde222c063bc61de23d4f434ad737d6e723ae3fe62fdd8db7299bb9fe`; start `2026-11-14T09:30:18.989391447Z`.

Read backend/proxy retained logs bounded to 6h and 2500 lines. Only allowlisted route/method/timestamp/duration/status emitted; backend logs lack status, proxy common access format supplies it. At screenshot's 10:48 UTC:

- 10:48:02 GET `/v1/podcasts/subscriptions` **200**, 58 ms; GET `/v1/podcasts` **200**, 45 ms.
- 10:48:18 subscriptions **200**, 21 ms; library **200**, 50 ms.
- 10:48:28 subscriptions **200**, 12 ms; library **200**, 28 ms.
- 10:48:36 subscriptions **200**, 17 ms; library **200**, 16 ms.
- 10:48:37 subscriptions **200**, 11 ms; library **200**, 26 ms.
- Coach GET at 10:48:22 **200**, 10 ms (does not establish its decode outcome).

Inspected `/app/data/podcasts/jobs.json` via `docker cp ... -` tar in process memory only. Printed aggregate counts and allowlisted field types, never owner IDs, credentials, URL/content values or private bytes. Exactly 1 subscription, 1 completed job, 2113 segments, same owner, exactly 1 matching feed/episode association. Job has `title: string`, feed_id/episode_id strings, segments array. Subscription episodes are objects with string id/title/url/published. API shaping from deployed-source Go nils matched preparation segments. No token/cookie replay, application store initializer, provider request, enqueue, sync or production mutation.

Ready means a saved completed preparation; audio playability was not asserted or tested.

## Candidate behavior

- Null/missing summary segments become empty local segment list; wrong types still fail. Required identity/state/progress remain strictly typed.
- Independent subscription/library completion applies immediately rather than awaiting both endpoints. Worker availability is advisory metadata, not a feed/library readiness gate.
- Failed endpoint retains its owner-scoped cache; stage + safe reason distinguishes response incompatibility, server, timeout and transport errors in all five locales. No raw response/error content, no false global offline assertion.
- Endpoint 401 now revokes native identity and clears session content immediately; late sibling result is fenced out.
- Banner Retry remains GET-only. No source refresh or AI enqueue.

## RED / GREEN evidence

`podcast-shape-red.log`: two expected failures, `keyNotFound segments` and `valueNotFound` at `items[0].episodes[0].preparation.segments`. Corrected decoder: all 3 focused tests green.

`podcast-appmodel-red.log`: actual AppModel harness caught delayed sibling withholding the successful feed, generic instead of stage-specific errors, and missing 401 invalidation (6 failed expectations). Corrected actual AppModel: 46 tests passed before final title/malformed-response additions.

Final verification:
- Full native Core: **20 XCTest + 68 Swift Testing tests passed** (`podcast-core-full.log`).
- Actual AppModel: **47 tests passed**, including production-shaped feeds, null segments, known title, malformed response classification without global offline, 503, timeout, partial cache, library suspended while feeds display, blocked history/provider independence, and 401 purge (`podcast-native-final.log`).
- Native CI discovery: **51 tests, OK, 1 skipped** (the existing optional built-bundle check); new strings additionally inspected in actual Release bundle: **8 keys × 5 locales present**.
- Ad-hoc signed Release simulator: **2 targeted UITests passed**, bundle signature verified. First UI attempt's 8-second delay elapsed during cold simulator startup; increased synthetic delay to 60 seconds, after which delayed-feed, partial error and explicit recovery all passed. This was a fixture timing issue, not concealed as product success.
- Final result bundle: `/Users/tinyserve/.hermes/cache/scratch/podcast-load-ui-final.xcresult`.
- Inspected screenshots in `/Users/tinyserve/.hermes/cache/scratch/podcast-load-shots/`: `4F611238-B80A-484C-804D-C765617B9831.png` shows successful feed during suspended library; `BBF14FE3-0740-4134-93A2-79379F918B5E.png` shows precise library/server error with feed retained; `CF768BD4-2262-48DF-90C4-E5499EC4C961.png` shows correct saved title and transcript; `A7CD971A-C8FE-47F3-B4BC-6FDFD1083C95.png` is recovery.
- Existing unrelated UITest main-actor warnings remain in Xcode output. No backend code changed. The above is the original candidate verification, superseded by independent review below.

## Independent review — 14 November 2026

Reviewed actual production diff and owner/session/cache boundaries. Added a Go overlay fixture (`native/ci/podcast_wire_fixture_test.go`) against the unchanged real server package/store, then decoded its serialized subscription and 2113-segment library with Swift using `python3 native/ci/verify_podcast_wire.py`. All fixture data is synthetic. No deployed store, bearer, provider credential, AI or production write used.

This reproduced one additional defect: a valid Go nil `episodes` collection rejected an empty subscription. RED `podcast-review-wire-red.log` captured `valueNotFound` at `episodes`; the minimal subscription decoder now accepts null/missing episodes while rejecting non-array values and malformed entries. Top-level `items` remains required and strictly typed, as the backend always emits an array. Required job fields, optional present fields, malformed segments, and legacy/current title precedence remain strict. Legacy `episode_title` cache and current `title` round-trip are covered.

Verification after review:
- Actual Go serializer → Swift: **6 focused XCTest passed**, including null summary segments, empty feed, canonical title, 2113 segments and wrong-type rejection (`podcast-review-wire-green.log`). Standalone Core has 23 XCTest (22 pass, 1 integration test skipped without fixture environment) plus **68 Swift Testing passed**; the skipped wire integration passed separately above.
- Native CI: **51 tests OK, 1 optional built-plist skip**; actual AppModel harness **48 tests passed**, including old title cache, failed reads, owner/origin isolation, immediate 401 purge and an uncancellable late sibling prevented from restoring private data. Metadata check then passed **3/3** against the actual Release app.
- Full unchanged backend `go test ./...`: **passed** (137.393s). First attempt hit a 180-second tool timeout; the bounded rerun completed.
- Signed Release simulator: **2/2 targeted UI tests passed** with realistic 2113-segment fixture; independent feed during delayed library, stage-specific error retaining feed, GET-only recovery, stable title and transcript. Strict bundle codesign verification passed.
- Result: `/Users/tinyserve/.hermes/cache/scratch/podcast-review-ui-final.xcresult`; log `podcast-review-ui-final.log`. Exported screenshots under `podcast-review-shots/`; inspected title/transcript `D89A0A0D-7A16-42FF-831E-BD272ACCA012.png` and retained feed/error `262D2DCF-6A7D-46FA-BB7C-65687A056F3A.png`.
- First review UI build failed type-checking a complex fixture dictionary expression; split into explicitly typed statements and reran successfully. No production workaround.
- Added-line security review and `git diff --check` clean. Scope is native podcast code/tests/docs only. Flame, outbox, catalog advisory and compact Coach remain inherited unchanged. Original dirty Diktat and parallel candidates were not touched. Backend deploy is neither needed nor performed.

## Apple publication — verified

- Released source: **`d3f2261499a5317b89055343fef61ff9297fe564`**, normal fast-forward push to main after fresh remote inspection; no force push.
- Existing workflow explicitly dispatched once with `publish=UPLOAD`: [run 43590037837](https://github.com/ptmt/KeineMagie/actions/runs/43590037837), **success**, exact `headSha` above.
- Validation job **132433256394** success; upload job **132433967379** success; cleanup success.
- Uploaded build **1.0 (2744.3.52)**. Upload-job log: `CURRENT_PROJECT_VERSION = 2744.3.52`, `ARCHIVE SUCCEEDED`, `EXPORT SUCCEEDED`, and **`UPLOAD SUCCEEDED with no errors` at 2026-11-14T11:36:07.1730010Z**.
- Push-only validation [43590033565](https://github.com/ptmt/KeineMagie/actions/runs/43590033565) also succeeded. No backend deployment or provider inference occurred.
- Local evidence: `/Users/tinyserve/.hermes/cache/scratch/podcast-review-upload.log`. Initial watcher tool timed out; resumed watching the same run, never duplicated publication.
- Apple processing, tester availability and physical-device behavior are not verified. Documentation follow-up is `[skip ci]` and not a second app build.
