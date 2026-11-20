# Coach-only native release — November 20, 2026

## Scope and provenance

Owner-authorized release of the Coach chat preview and composer plus menu only. Isolated release worktree: `/Users/tinyserve/Projects/KeineMagie-coach-menu-release`, branch `release/coach-menu-only`, based on remote `7b87555bc6dd0080b87bfceefaffe26245fd553a`.

Full original commits `984e34ed7b8d1f840e10a386aa8fe641090d9412` and `dd949f93b2e1cc057efdac1d42c9c3c6119538e8` were cherry-picked as `5ac4c03` and `f2ee676`. Production changes are limited to `native/App/CoachView.swift` and two additive five-locale catalog keys. Simulator-only transport probes and Coach UI regressions accompany them. The release worker independently reviewed the combined source, command routing, input/owner gates, catalog preservation and test changes.

No server/web/workflow changes. No Dictation policy-2, hybrid assessment, speech settlement candidate, or unfinished native Dictation implementation is included. Those remain in `/Users/tinyserve/Projects/KeineMagie-dictation-manual-hybrid-integration`; its `9577f34` checkpoint is not release acceptance. No production data, historical budget holds, provider credentials, AnyProgress code or protected dirty originals were modified. The $10 cap and fail-closed unknown-receipt handling remain untouched; this release does not clear any old holds or establish remaining budget.

## Exact-source local validation

- Full `python3 -m unittest discover -s native/ci -v`: 64 tests, zero failures, one pre-build effective-plist skip. The same discovery suite also passed against a clean archive of base `7b87555`.
- Post-build effective-plist suite: all 3 passed, closing that pre-build skip.
- Full Swift Core: 100 XCTest cases, four opt-in wire skips, zero failures; 84 Swift Testing cases passed. Native CI includes 119 actual AppModel/lifecycle tests and the actual Go-to-Swift Coach wire check. Separate opt-in Dictation policy bridge, Coach two-client/race and Podcast Go-to-Swift runners also passed, exercising the normally skipped bridge cases.
- XcodeGen, unsigned Release simulator `build-for-testing`, shell syntax and both tracked app plist checks passed. Local Xcode 27.2; hosted Xcode is separately pinned by the existing workflow.
- Source inventory: 503 baseline test identities become 510. One chip-to-menu test was renamed and adapted to the replacement control; seven tests were added, no regression was silently dropped. Existing catalog keys/values remain exact; only `coach.actions` and `coach.menu.progress` were added in all five locales.
- Existing normal-device result was read with `xcresulttool`: **33 passed, zero failed/skipped**. All 207 tracked native source hashes matched that receipt before the test-only fixture-path improvement below. Production native sources remain identical.
- Small-device coherent acceptance: **33 passed, zero failed/skipped**. Same 30 Coach tests plus cross-tab WAV playback, explicit Stop and Back/draft tests. No test was removed to avoid fixture saturation.

### Fresh fixture, not a production-limit bypass

The previous small suite failed two setup POSTs because its reused synthetic store contained 30 records. The existing store was neither reset nor edited. The test harness now accepts `KM_DICTATION_UI_FIXTURE_ROOT`, falling back to its existing path for compatibility. A newly allocated scratch directory, new synthetic owner and generated eight-second PCM WAV serve this release's complete small suite at loopback 8799. The fresh authenticated history was verified empty before starting and contained four records after all 33 tests passed. The fixture listener was stopped and both borrowed simulators were verified shut down afterward.

A scratch-only Go `-overlay` changes the opt-in fixture's internal lifetime from 20 to 60 minutes and gives the synthetic owner a release-specific subject. It does not alter production handlers, limits, admission or ledger logic. `go test -timeout 65m` bounds the process. The generated `.xctestrun` supplies only the root path; no fixture token is committed. Existing small simulator `56A70197-59DE-4410-9E76-25272244E9C8` is reused with parallel cloning disabled, without erasing or creating a device. Normal receipt device: `93E1113F-6736-4CCB-827D-0E2F1C3876EA`.

Working evidence: `/Users/tinyserve/.hermes/cache/scratch/coach-only-release/`. Durable release summaries and source/test manifests are under `docs/evidence/coach-only-release/`. Earlier diagnostic failures remain preserved under `docs/evidence/coach-composer-menu/`.

## Publication gates

Local publication gates passed: coherent small acceptance, unchanged production native-source manifest, combined test inventory/security review, and protected original hashes (KeineMagie 304/304; AnyProgress 13/13). No substantive security or logic issue was found in the Coach-only diff. Normal non-force push, remote readback and exactly one `ios-testflight.yml` dispatch with `publish=UPLOAD` remain to be recorded below.

Backend public certificate-validating IPv4 health returned 200 and guest Coach API 401. Backend container `4a244c2b7be43da15c9afd7815a355dd604722632aad930893078ed3e6eadc77`, image `sha256:fdff5214c556b8e2bd55b3a406f8f5264990e7b4f6a70ed8207eba1bad2d7a82`, source `a6699b034eb4584c533a6c2268ea35bafd040a2f` are unchanged. The server workflow is path-filtered to server/web/its workflow, so this native/docs-only release should not trigger server publication or require deployment. No rollback or ledger operation is authorized or needed.

Apple upload, processing, tester availability, physical-device behavior and spoken VoiceOver are distinct gates. Simulator screenshots and synthetic transport tests do not establish real-provider quality or actual account inference.
