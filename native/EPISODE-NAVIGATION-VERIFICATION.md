# Native episode navigation and stored learning

Independent native review completed; scoped release prepared against existing web/server contracts. Release run and Apple upload evidence are recorded below after exact-SHA readback.

## Native functionality

- Episode reader has Summary, Vocabulary, Recommendations and Transcript destinations. Displays stored narrative/topics, saved words/favorite/status and recommendations; grounded citations validate exact quote and zero-based segment index before jumping into the transcript.
- Transcript timeline slider, strict `minutes:ss` jump, case-insensitive source/translation search, highlighted results and previous/next matching **segments** (not individual word occurrences). Long episodes use indexed windows; previous/more controls retain access to every segment. Synthetic 2113-segment coverage includes jumps to 2012 and translated search to 2050.
- Profile is reachable from episode and Account. DE/RU self-assessment supports unknown/A1–C2, explicit Save, server readback and dated assessment history. No automatic CEFR promotion.
- New copy is translated DE/EN/RU/ES/FR. Existing catalog values are unchanged; generator now retains 70 pre-existing podcast catalog keys previously missing from its source.
- Episode analysis/vocabulary GETs load independently; a stalled vocabulary read cannot hide a completed summary. Partial errors retain saved data. Requests disable URL caching, validate IDs/languages and use the existing bearer transport.
- Owner/origin-scoped protected `learning` snapshot uses existing revision/lease fences. Cache hydration precedes online readiness; offline reads require existing secure session provenance and cannot write. Identity changes and 401 reject late completions and clear private state; logout cleanup includes learning. No credentials are stored in content caches.

## Audio is not implemented

The slider navigates the **transcript**, not audio playback, and says so persistently. Inspection of `server/podcast.go`, sources/permalink handlers and resume storage found no owner-authenticated media/range endpoint. Internal `mediaPath` is worker storage, not an exposed playback API. `job.url` may be a publisher source, not a stable authenticated playable representation. No empty Play button, fabricated player, remote publisher request, new server media endpoint or automatic AI job was introduced.

Saved summaries/vocabulary/recommendations are read-only in this iteration. New generation/resume and word editing remain web actions. Opening readers/profile and navigating timestamps issue no inference requests. No live credentials, personal data stores, real provider or paid inference were used.

## Actual verification

- RED→GREEN: missing timestamp navigation and learning request APIs; missing timeline control; cache logout retention; stalled vocabulary blocking summary. Evidence logs under scratch.
- `swift test --scratch-path /Users/tinyserve/.hermes/cache/scratch/km-podcast-core`: **11 XCTest + 64 Swift Testing passed** (`km-podcast-core.log`). Existing `native/test-core.sh` fails under standalone CLT because XCTest is unavailable; full Xcode Swift toolchain works.
- `KM_BUILT_APP_PLIST=.../Release-iphonesimulator/KeineMagie.app/Info.plist python3 -m unittest discover -s native/ci -v`: **44 passed**, includes **24 real AppModel lifecycle/dataset/learning tests** in a synthetic Swift package (`km-podcast-ci-final2.log`). Covers coalescing, late reset, partial failure, independent readiness, offline cold model relaunch, explicit PUT→GET readback and 401 provenance invalidation.
- Ad-hoc signed **Release iPhone 17e / iOS 27.2**: existing Podcasts + OfflineHistory suites **10 passed** (`km-podcast-release.xcresult`); final reader/profile/offline learning cold-relaunch tests **2 passed** (`km-podcast-final.xcresult`). `codesign --verify --deep --strict` passed for Release app.
- Screenshot inspection confirmed populated segment 2012 citation jump, selected/highlighted translated match 2050, working slider position, vocabulary and CEFR B2. These are synthetic fixtures, not live-account evidence. The existing in-memory simulator transport was extended; no production fixture or credentials added.
- `git diff --check` clean; added-line secret/unsafe evaluation scan empty. Parent independent review still required before release.

## Evidence paths

All rooted at `/Users/tinyserve/.hermes/cache/scratch/`:

- `km-podcast-core.log`, `km-podcast-ci-final2.log`
- `km-podcast-release.log`, `km-podcast-release.xcresult` (full regression run)
- `km-podcast-final.log`, `km-podcast-final.xcresult` (final targeted run)
- `km-podcast-final-shots/manifest.json` (final attachments, original UUID filenames)
- `km-podcast-release-shots/synthetic-timeline-{initial,citation,search,vocabulary,profile}.png` (reviewed screenshots before final language-label fix; final attachments supersede them)

## Independent review and release gate (12 November 2026)

- Reproduced a substantive CEFR race with a suspended PUT: an ordinary GET superseded the save request, leaving native B1 after the server saved B2. `km-review-race-red.log` records the failed real AppModel expectation. Fixed per-language write ownership/coalescing; an assessment can supersede an older read, but reads/duplicate writes cannot invalidate an active assessment. Ordinary loads now use one GET; explicit Save remains PUT → exact-target GET. Reset and 401 stay fail-closed. `km-review-race-green.log` and final lifecycle suite pass.
- Fixed citation navigation leaving the slider at the previous position when the transcript subtree was absent. Returning from Summary now synchronizes timeline to selected segment 2012 (`335:20`), asserted in XCTest.
- Dark **maximum accessibility XXXL** on populated Release iPhone 17e exposed truncated timeline labels and transcript-only disclaimer; separated time labels from slider and allowed disclaimer wrapping. Both timestamps and full disclaimer now fit. Section strip remains intentionally horizontally scrollable (partial neighboring label is a scroll affordance); all destinations were reached by actual swipes. Search text fields scroll/truncate long queries normally. Assessment history is reachable by vertical scrolling at this size.
- Final independent tests: **11 XCTest + 65 Swift Testing** (`km-review-core.log`); **44 Python CI tests, no skips**, including **27 real AppModel tests** (`km-review-ci-final.log`, processed Release app plist supplied). Added exact citation negative/out-of-bounds/fabricated/translation-only rejection coverage, suspended profile read/write/reset and profile 401 tests.
- Release populated simulator: **2 dark maximum-Dynamic-Type tests passed** (`km-review-dark-ax-pass.xcresult`) and **11 light/default-size Podcasts + OfflineHistory regression tests passed** (`km-review-regression.xcresult`). Dark cold relaunch restores saved summary/profile and disables offline changes. Final dark screenshot attachments exported under `km-review-dark-ax-pass-shots/manifest.json` and visually inspected (timeline citation/search, saved B2).
- Strict ad-hoc signature verification passed. Added-line security scan empty, `git diff --check` clean. Localization semantic comparison: no removed keys or changed pre-existing values; 31 added keys. No signing/workflow/backend changes, real credentials, paid inference or deployment used during review. Independent review performed by a fresh reviewer separate from implementation; local baseline regressions exercised without stashing unrelated work.

Remaining: App Store processing/tester visibility, physical-device/live-account verification, actual playback server contract, native explicit analysis generation/word editing. This release is **transcript navigation only**, not full podcast parity. Unrelated `spikes/` and `web/tests/__pycache__/` preserved.

## Release evidence

- Shipped native source: `c798c9d791c319a7fe0dd5351bf767d3adb31b7d` on existing `main`.
- Existing push-triggered [iOS TestFlight run 43316659380](https://github.com/ptmt/KeineMagie/actions/runs/43316659380), exact `headSha` above, read back **completed / success**. `validate` and `testflight` passed; signing cleanup passed. No duplicate dispatch or backend deployment.
- Marketing version **1.0**, build **2730.57.80**. Actual runner output: `2026-11-12T22:10:24.3948890Z ** ARCHIVE SUCCEEDED **`, `22:10:25.7970960Z ** EXPORT SUCCEEDED **`, `22:14:01.9132350Z UPLOAD SUCCEEDED with no errors`, `22:14:01.9180020Z Apple upload command succeeded. Check App Store Connect processing and TestFlight availability.`
- Raw CI evidence retained locally at `/Users/tinyserve/.hermes/cache/scratch/km-review-release-ci.log`; exact run/job handles: validation `131526320451`, upload `131528357902`. Apple processing, tester assignment/visibility and physical installation remain unverified; upload is not availability.
