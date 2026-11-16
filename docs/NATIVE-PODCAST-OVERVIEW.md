# Native podcast overview — local candidate

## Scope and baseline

- Isolated worktree: `/Users/tinyserve/Projects/KeineMagie-native-podcast-inline3`, branch `candidate/native-podcast-inline3`.
- Fresh `git fetch origin` confirmed `origin/main` at `6a45610a1720857e7bc532ba9f9d88a02779bc1e`. The original dirty `/Users/tinyserve/Projects/KeineMagie` is not edited; the released Coach worktree and AnyProgress are untouched.
- Compared actual `web/app.mjs`, `web/core.mjs`, `docs/PODCAST-LIBRARY-OVERVIEW.md`, native `PodcastAPI`, `PodcastStore`, reader and Go coverage types. This is **local-only**, not a TestFlight/server release. Independent parent review remains mandatory. No push, deployment, provider calls, TTS, credentials or private user history.
- Coach corrected-full-sentence feedback is a separate next task. No Coach, translator, Dictation or backend behavior is bundled here.

## Native behavior

- Each podcast is a native plain-list section with a 52-point source artwork thumbnail, literal title and optional source author. Header opens the existing full-feed view. A quiet, separately tappable **All episodes** link also opens it.
- Up to three latest episodes **per feed**. Valid publication dates sort descending; equal/unknown/invalid dates retain source order, after valid dates. Supported source dates include ISO 8601 (including fractional seconds), calendar dates and RSS date formats. The backend's existing retained feed episode bound is unchanged; this does not fetch unlimited remote history.
- Episode identities are scoped by the surrounding feed section. Actual job association retains the existing feed + episode IDs and legacy canonical-source-URL fallback; an explicitly linked job is not borrowed by another feed with the same episode ID.
- A prepared title opens the existing native reader/detail. An unprepared title opens the existing feed preparation UI filtered to that episode, with a full-feed link. Selection never starts AI. The existing explicit Prepare path, same-owner pending store, retry and cancel operations remain in use.
- Each row shows actual job stage, active-stage progress, and optional server `coverage`. `translated_segments / recognized_segments` is labeled **translated passages**, not sentences or playback progress. Zero/missing recognized totals are omitted. Optional `favorite_passages` is shown as **Starred passages**, separate from vocabulary favorites. No fabricated counts or inferred listening state.
- Five interface locales (`de/en/ru/es/fr`), Dynamic Type, system light/dark styling and minimum 44-point navigation/action targets. Episode controls are siblings of their navigation link, not nested buttons. No extra large cards or permanent import form.

## API, caching and lifecycle

- Same two concurrent batch metadata GETs: `/v1/podcasts/subscriptions` and `/v1/podcasts`. No per-episode detail GET is added to render the overview, regardless of feed count. Existing optional artwork GETs and reader learning/profile GETs are distinct from this batch pair; they are not AI generation.
- Additive optional native DTO fields: subscription `author`, job `coverage`. Existing owner-scoped Codable podcast snapshots retain them; older snapshots/server payloads without these fields still decode.
- Same-owner data remains visible during refresh and endpoint failure. Initial loading, verified empty and failed reads remain separate. The two endpoints still apply independently. Pull-to-refresh awaits a separate read task to avoid cancellation inherited from SwiftUI redraw, with the existing owner/generation fences retained.
- Existing foreground active-job polling and pending-operation coalescing remain unchanged. Native polls at its existing three-second cadence, not web's five-second cadence; it remains active-scene scoped rather than a new web-router implementation.
- Read refresh replaces batch coverage, so changed passage stars update the existing row; failed reads retain the last acknowledged counts. Native does not yet offer passage-star mutation controls in its reader. Changes made in web become visible on native refresh (or existing active-job polling), not through push notifications.
- Existing owner reset/401 cache revocation, trusted read-only restoration, explicit preparation ownership and stale-response fences are retained and exercised by the AppModel harness. The feature does not create a second cache or a view-owned preparation task.

## Verification

All signed-in UI evidence uses the simulator-only synthetic transport and synthetic source text, not production account data. Release screenshots are actual app rendering, not recreated designs.

- `swift test` in `native/Core`: **58 XCTest cases, zero failures, one Go-wire integration skip**, plus **72 Swift Testing tests passed**. The skipped integration is separately executed by the next command. Log: scratch `podcast-core-full.log`.
- `python3 native/ci/verify_podcast_wire.py`: **six wire tests passed**, including actual Go-store serialized author and `coverageFor` passage metadata (2,113 recognized, zero translated, one starred), null transcript summaries and owner isolation. Log: scratch `podcast-wire.log`.
- `python3 native/ci/test_connection_lifecycle.py`: **95 real-AppModel harness tests passed**. New checks cover pure overview projection with exactly two batch GETs, changed star counts replacing previous coverage, failed-refresh retention and late read after reset. Existing suites exercise 401 revocation, trusted cached-owner restoration, endpoint independence, pending preparation coalescing/cancellation/retry and unchanged Coach/translator/Dictation behavior. Log: scratch `podcast-appmodel.log`.
- `python3 -m unittest discover -s native/ci -p 'test_*.py'`: **54 tests, zero failures, one metadata-test skip** (effective built plist requires an environment path); this run also executes the 95-test AppModel harness. Log: scratch `podcast-native-ci-final.log`.
- Final-source `xcodebuild … -configuration Release -jobs 2 ONLY_ACTIVE_ARCH=YES build-for-testing`: **TEST BUILD SUCCEEDED**. Log: scratch `podcast-build-final.log`. This verifies compilation of the final source, not the blocked expanded UI execution. The three metadata tests also passed with `KM_BUILT_APP_PLIST` pointing at this built app, covering the CI skip above.
- Actual **Release XCTest, iPhone 16e / iOS 27.2**: **two UI tests passed, zero skipped**, checked from xcresult summary, not merely xcodebuild exit status. `testInlineThreeReaderBackAndFullFeed` exercises exactly three visible rows, excluded fourth, real nonzero saved counts, zero/unknown omissions, 44-point row/full-feed links, saved reader at `0:00–0:08`, Back, and full four-episode feed. `testFiveLocalesAndLargeType` launches all five locales at accessibility XXXL, checking row bounds and labels. Bundle: scratch `podcast-inline-green3.xcresult`.
- TDD evidence: sort/author and coverage tests first failed on absent DTO projections; real Release UI first failed on missing inline rows. Subsequent Release assertions detected incorrectly double-formatted numeric localization (rendered zero counts); fixed to pass arguments directly through `AppL10n.text`, then both UI tests passed. The corrected actual overview, reader and Russian XXXL images were inspected.
- Actual verified screenshot directory: `/Users/tinyserve/.hermes/cache/scratch/podcast-inline-verified-evidence/` with `test-summary.json`, export `manifest.json`, `overview-three-saved-zero-unknown.png`, `overview-reader-zero-timestamp.png`, `overview-all-four.png` and `overview-large-{de,en,ru,es,fr}.png`. The large-type screenshots cover the initial viewport, not every scrolled row.

### Remaining verification blocker

Expanded Release tests were added for pull-to-refresh star updates/error retention, duplicate IDs across feeds, explicit active-job cancel/retry, keyboard and Profile. Their subsequent runs **did not reach test execution** after simulator/test-runner startup stalled; those checks and the full existing Podcast UI suite are **not claimed passed**. A new isolated iPhone SE also stalled in system migration. The host showed load averages 51/155/244 and 2,293 processes (1,661 simulator-related); this is evidence of severe concurrent load, not proof of a process-limit breach. Both task-created simulators were stopped without touching other projects. Small-device/dark-mode expanded acceptance remains a parent-review gate. The earlier two-test Release run is genuine executed evidence, not substituted for these missing gates.

## Release gates / limitations

- Requires independent parent code/UI review before any commit is integrated or released.
- No real provider pipeline, paid inference/TTS, authenticated production account, physical device or TestFlight verification is claimed.
- Native reader still uses its existing read-only transcript/learning/profile features; this is library overview parity, not implementation of every web reader action.
- The existing batch jobs response still carries transcripts; payload optimization and broader polling/action lifecycle redesign are outside this candidate.
