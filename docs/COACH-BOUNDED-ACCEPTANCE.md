# Coach bounded acceptance and release preparation

## Candidate and integration boundary

Reviewed baseline: `9117357fa6ba6d97bcd7d5c51f8182b03f31c833`.
Bounded follow-up: `0f018c6` on `coach-chat-iteration`.
Fresh release worktree: `/Users/tinyserve/Projects/KeineMagie-coach-release-fresh`, branch `release/coach-chat-fresh`, created from freshly fetched `938eab7fe574ae01bd8fe3c7d0f9a28bed0f31a8` (Diktat released source `66136702239e98e61ed828e517cb0f7a54b76aca`). Local integration commits `d28505f` and `43f6da5`; no push/deploy/upload.

An earlier preparation worktree `/Users/tinyserve/Projects/KeineMagie-coach-release-integration` at `a799b93` is **superseded**, not the release target.

## Bounded native acceptance

- XCTest accessibility snapshots exposed empty explicit field labels and Send preceding Message. Added localized Answer/Message labels and a contained composer accessibility group with local sort priority. RED snapshot and corrected GREEN `coach-acceptance-ax4.xcresult` retained. Uses one captured hierarchy for order; repeatedly enumerating live descendants mixed snapshots and gave spurious index comparisons. This verifies AX hierarchy/labels, **not actual VoiceOver spoken traversal**.
- Added a simulator-only, fixture-gated injected environment seam. The read-only SwiftUI `accessibilityReduceMotion` cannot be mutated; a writable app environment override feeds the **same `system || override` production condition** for arrival, scrolling and disclosure. No private defaults or invented simulator switches. UI telemetry recorded `static;system=false;injected=true`. Actual OS Reduce Motion and VoiceOver remain owner-assisted checks; `simctl ui` documents appearance/contrast/content-size only.
- Normal and reduced runs use actual signed Release simulator on iPhone 17 Pro / iOS 27.2, UDID `775A82E7-8B2D-4117-B3DE-2BAFDD234E48`. Same fixture supplies a versioned clarification and immediate seen response; jump indicator disappears and return navigation retains content.
- Actual `simctl io recordVideo --codec=h264` recordings and native-frame sampling show normal arrival is not canceled by receipt rendering. Native frames 300–311 (PTS 12.258333–12.405000) progressively increase sampled ink from 3.5918 to 25.5508; final remains about 25.66. Vision confirms sustained fade/crossfade, not a discernible slide claim. Reduced frames 350→351 jump directly to final content, then remain static; frame 351's unread accent disappears in frame 352 while content remains. These are simulator frames, not physical-display timing attestation. Initial populated history and tab return appear directly without entrance fade in the inspected sequence.

Artifacts under `/Users/tinyserve/.hermes/cache/scratch/`:
- `coach-frame-animated.mp4`, `coach-frame-reduced.mp4`
- `coach-frame-animated-samples.json`, `coach-frame-reduced-samples.json`
- `coach-arrival-native-frames.png`, `coach-reduced-native-frames.png` (vision inspected)
- `coach-frame-animated.xcresult`, `coach-frame-reduced.xcresult` (one passing test each)
- `coach-acceptance-ax4.xcresult` (one passing AX test)
- `coach-acceptance-motion2-shots/C8DB6212-C53F-467D-9706-B3A4BCDC7A58.png` (arrival screenshot inspected)
- `coach-acceptance-batches.json` (machine-counted original ten tests, five serial two-test batches)

Original ten Coach UI cases all have successful runs: batches 1/2/4/5: 8 passed; batch 3: Profile passed, locale test failed on missing keyboard focus, unchanged isolated `coach-locales-repeat.xcresult` then passed all five locales. No timeout counted as success. Added three distinct tests pass in the dedicated bundles above, giving thirteen distinct Coach cases with successful executions, not a claim of one pristine thirteen-test run. The initial label failure and transient locale failure remain recorded.

## Simultaneous independent clients

`python3 native/ci/verify_coach_two_clients.py` starts an opt-in authenticated loopback **actual Go handler and private temporary store**, then exercises two separate production AppModels, sessions and cache roots. Concurrent GET does not acknowledge invisible content; simultaneous five-hour entry admits exactly one free offer; concurrent visible receipts converge; new feedback is unread; a delayed old-revision callback cannot see it; the fresh visible receipt converges across clients. All network/provider behavior is synthetic, including the assessment transport. Fail-closed Keychain stubs caught missing injected dependencies during harness construction; no personal credentials were read.

Actual run: **72 AppModel tests passed**, actual Go bridge race run passed. No simultaneous two-simulator or physical-device UI claim. Existing browser fixture concurrency/visibility tests and handler CSRF gates are complementary, not a substitute for that manual UI gate.

## Repeated candidate tests

- Node: **85 passed**.
- Native Python CI: **51 tests, one skip, passed**; underlying actual AppModel **72 passed** (two-client test only does its assertions in the dedicated opt-in bridge run).
- Go→Swift Coach wire **8 states passed**.
- Full Go race initial run hit existing `TestPodcastSIGKILLRecovery/recognition` cleanup timing assertion; unchanged focused Coach/Assessment/podcast rerun passed, then unchanged **full race repeat passed**. `go vet ./...` passed. No assertion weakened.
- Ad-hoc Release simulator signature `codesign --verify --deep --strict` passed; no physical provisioning claim.

## Integration preservation and release stop

Preserve Diktat AppModel and ContentCache changes, all Diktat localization keys, DictationView/tab/fixture, server router/static registration and Docker Diktat assets. Resolved localization/Docker conflicts additively; CI harness includes **both** Diktat resolver checks and the two-client Coach check. Integration verification is recorded below after execution.

Integration verification at source `43f6da5` (documentation-only commits follow): full Go race/vet passed; Node **104 passed**; native Python CI **53 tests, one skip, passed**, executable AppModel **75 passed**, dedicated real-Go/two-AppModel run **75 passed**; Core direct `swift test --package-path native/Core`: **51 XCTest executions, one skip, zero failures + 68 Swift Testing passed**; actual Go→Swift Coach decoder **8 states passed**; actual Chromium Coach fixture suite passed. The legacy `bash native/test-core.sh` failed to locate XCTest on this toolchain; direct SwiftPM alternative above actually passed, no fabricated script success.

Fresh generated/ad-hoc signed Release simulator build passed **2/2** focused AX/reduced-motion tests in `coach-integrated-ui2.xcresult`; `codesign --verify --deep --strict` passed. Exported and vision-inspected `/Users/tinyserve/.hermes/cache/scratch/coach-integrated-shots/79EB6EEB-5B78-4CD5-964B-EB7ED69A512D.png`: clarification readable, no visible error, Dictation tab retained. First build attempt failed because fresh worktree has no generated Xcode project; `xcodegen generate` from unchanged signing-configured `native/project.yml` fixed prerequisite, not production behavior.

Parsed all **368** baseline localization entries from `938eab7`: every value unchanged, including Diktat's human-readable keys (not just the one `dictation.*` prefixed key). ContentCache, DictationView/Core Dictation, server Diktat implementation and web Diktat are byte-unchanged. AppModel diff is Coach-only; MainTabs adds only fixture environment injection and retains real DictationView. Docker includes both Diktat assets and new Coach module. No conflicting markers or dirty tracked files.

Preparation stopped without deployment. The subsequent final-release request explicitly authorizes normal backend release and a separate exact-SHA Apple UPLOAD (not App Store review). Final review found the intended successful-seen nonreplacement assertion missing from the fresh harness; it is now present and passes. An isolated in-memory mutation replacing the conversation with the receipt response fails that exact assertion (75-test harness, one expected failure); the unmodified harness passes all 75. Repeated final gates: 53 native CI (one skip), actual two-AppModel bridge 75, Go race/vet, Node 104 and Chromium fixture passed. No paid calls. See `COACH-CHAT-RELEASE.md` for delivery readbacks. Eventual release must reread the current durable Compose override, not restore a stale copy. Preserve dedicated read-only secret mount/environment and the authoritative monthly ledger's **one existing USD 1 hold** exactly once; never restore historical application data or reset the budget. Do not create paid Coach AI or TTS calls. Original dirty main, Diktat worktree, personal credentials and production ledger remain untouched.

Manual gates: owner actual VoiceOver spoken swipe order/actions and OS Reduce Motion enabled pass; optional simultaneous native/web UI on two actual devices. Automated AX snapshots plus injected reduced-motion branch and two independent AppModels do not assert these physical checks are complete.
