# Coach + weekly activity — integrated local candidate

Worktree `/Users/tinyserve/Projects/KeineMagie-coach-activity-local`, branch `integration/coach-activity-local`. Verified common base `39ed59dc534c600c1d823f573ad7c35474791c54`; cherry-picked stable Coach `52c52ec3a978acd3818d468e891f18451e79394b` and weekly activity `596379d`, `5d93b31`. Original dirty working files and both candidate branches were not edited. **Local only: no push, deployment, Apple upload, production mutation or paid application AI/TTS call.**

**Incomplete requirement:** Podcasts cannot yet count fully listened episodes. The source has no supported podcast audio player, authenticated media/range contract, or actual playback-ended/coverage events. This is explicitly unsupported/unknown, not a verified zero. The remaining implemented subset is verified below; this is not full-feature release approval.

## Evidence audit / count semantics

| Source | Durable evidence and attribution |
| --- | --- |
| Translator | `account_translation.go` saves owner history after a successful completed result and session revalidation. `CreatedAt` is assigned after provider success. Count one nonempty saved result per immutable ID, reading the entire locked owner store rather than the newest-100 display list. No request/admission/followup counts. Missing dates remain undated. Shared legacy history is excluded. |
| Coach | One settled explicit Check per exercise turn, correct/wrong/ambiguous alike. Read current and prior attempts; preserve the original Check date across rechecks. Failed/pending/canceled work, skipped answers, generation and discussion do not count. A completed prior check survives a later failed recheck. Observation reset/exclusion is not deletion. |
| Dictation | One checked attempt ID regardless of correctness, including partial dictation checks. Existing receipt records the Check date and duplicate checks cannot replace it. Optional hybrid inference failure does not undo the saved deterministic Check. Never substitute item creation for a missing check date. |
| Podcasts | Worker preparation, download/transcription/translation and transcript navigation are not listening. `EpisodeReaderView.swift`, `episode.mjs` and `episode-reader.mjs` have no supported podcast player completion path. Dictation playback is separate and cannot supply podcast evidence. |

The three supported sources already have durable owner-scoped completion evidence. No duplicate private-reference ledger was added. A future podcast implementation needs a supported playback contract plus an actual natural-ended event **and genuine full-duration coverage**. Seek jumps must reset the observation anchor and must never credit skipped intervals; a conservative contiguous full listen is acceptable. Ended alone, near-end position, elapsed wall time, preparation completion and player starts are insufficient. No unhooked endpoint or self-report completion checkbox pretends to implement this.

All seven API days remain `partial`, including observed zero. Retained/deleted/undated history cannot establish complete coverage. `known_count` is a lower bound. Additive `counts` maps give per-source observed counts; `sources` distinguishes retained, unsupported and unavailable storage. Swift accepts older payloads without `counts`. Day details show the four sources and the all-history undated total in DE/EN/RU/ES/FR. The locale-week strip remains **30pt total, seven 30×30pt squares** with a separate today outline.

## Privacy and compatibility

- Read only the authenticated opaque owner's hashed history under the existing lock. No new private cache, event journal, provider request or background mutation. Source text/IDs never enter the activity response.
- Deletion removes retained counts on the next read, including after reopening storage. The existing spent translation receipt prevents replay from recreating a deleted result; real authenticated handler tests cover this. Logout revokes access/pending work rather than erasing server account history.
- Existing generation/cancellation/401 fences remain; breakdowns use the exact owner/week/timezone snapshot key. Account-generation changes clear an open detail and snapshot.
- Preserve `context_translation` strict generation/evaluation and old-schema compatibility, source/result pairing, contextual assessment, daily admission and owner fences. No calibrated difficulty dots or skill-scheduling/adaptation-policy changes.

## Presentation and inspected UI

Incorrect settled verdict: subtle red; correct: subtle green. Exercise/coach/pending/failed/uncertain surfaces stay neutral. Submitted answers and discussion messages have a separate adaptive blue tint. Literal verdict text remains; color is not the only status signal. Existing Stop, recheck, Earlier, independent discussion draft and exact submitted answer are preserved.

Source RGB contrast tests for explicit secondary text pass at minimum **6.68:1 light / 7.48:1 dark** across the selected surfaces. Actual Release screenshots were inspected for normal and small light/dark correct/incorrect/pending and error states. This is not spoken VoiceOver or physical-device certification. Day details use the native alert; on SE the long explanation exceeds the initially visible area while OK remains visible. Scrolling that explanation was not separately exercised. Maximum Russian Dynamic Type verifies the strip's bounds, not full-chat accessibility usability.

## Executed verification — November 22, 2026

Durable receipts and original unmodified screenshot bytes are in `docs/coach-activity-integration-evidence/`; full xcresult/build artifacts remain under `/Users/tinyserve/.hermes/cache/scratch/km-integrated-*`.

- **Full Go race suite + vet pass** on integrated sources (101.351s); clean integrated baseline `0c346dc` also passes (102.175s). An initial archive accidentally contained only the server subtree and failed static-asset tests; a corrected full archive passed. This was setup failure, not a product regression.
- **Full Core: 112 XCTest, 5 expected skips, zero failures; 89 Swift Testing pass.**
- **Real AppModel harness: 124 pass**, plus focused Coach/daily harness **16 pass**. Source guards: contrast 2, compact 2, activity integration 2 pass.
- **Node: 178 total, 177 pass / 1 existing skip / zero failures.**
- **Actual Go→Swift wire:** authenticated Activity response includes a saved translation and accurate source count; five Activity tests pass with `ACTIVITY_WIRE_PATH`. Ten actual Coach handler snapshots decode, including context translation and legacy schemas. Focused Go race selection: 26 top-level tests pass.
- **Release UI: 28/28**, four serial runs of the same seven selected tests: normal light 7, normal dark 7, SE light 7, SE dark 7. Parsed xcresult counts, zero failures/skips/runtime warnings. Tests cover fixed 30pt geometry, week navigation, count refresh after a real synthetic Check response, source details, Russian AXXXL unknown-not-zero, pending/separate answer/result, correct alternative, Stop/cancellation and transport error preserving drafts. Native transport is explicitly synthetic; no live model-output claim.
- **36 original XCTest PNG attachments** retained with SHA-256 manifest. Representative verdicts, pending, error, updated count, source details and large-type strip were inspected. Device IDs: normal `93E1113F-6736-4CCB-827D-0E2F1C3876EA`, SE `56A70197-59DE-4410-9E76-25272244E9C8`; no clones/new devices, serial exclusive testing. Both returned to original dark appearance and confirmed shut down.
- Independent read-only Codex review (`gpt-6.1-sol`) found **no concrete logic/security defects in the delivered subset**, but returned `passed:false` for the documented missing podcast completion requirement. Its native-rendering verification gap was subsequently covered by the UI runs above. No paid external design reviewer was invoked.
- Added-line security pattern scan, conflict-marker scan, `git diff --check`, structured JSON duplicate-key parsing and both parent localization key/locale unions pass.

Implementation used observed RED→GREEN slices for retained translations, per-source wire fields, optional Swift decoding, semantic palette wiring, day details and owner-key clearing. Coding-agent sandbox initially blocked sockets and shared Git index writes; host-side full suites and parent commit resolved those execution restrictions. Failed sandbox receipts remain in scratch and are not reported as passing tests.

## Reproduce

```sh
cd /Users/tinyserve/Projects/KeineMagie-coach-activity-local
(cd server && go test -race ./... && go vet ./...)
(cd native/Core && swift test)
python3 native/ci/test_connection_lifecycle.py
node --test web/tests/*.test.mjs
ACTIVITY_WIRE_PATH=/Users/tinyserve/.hermes/cache/scratch/coach-activity-wire.json go test -C server -run '^TestActivity' .
ACTIVITY_WIRE_PATH=/Users/tinyserve/.hermes/cache/scratch/coach-activity-wire.json swift test --package-path native/Core --filter ActivityTests
python3 native/ci/test_coach_wire.py
(cd native && xcodegen generate)
# Borrow only the approved existing device, set light/dark, and use a fresh result path.
xcodebuild -quiet -project native/KeineMagie.xcodeproj -scheme KeineMagie -configuration Release \
  -destination "platform=iOS Simulator,id=$UDID" -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -derivedDataPath /Users/tinyserve/.hermes/cache/scratch/km-integrated-derived \
  -resultBundlePath "$FRESH_XCRESULT" \
  -only-testing:KeineMagieUITests/ActivityUITests \
  -only-testing:KeineMagieUITests/CoachStableChatUITests \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test
```

Still unverified/unimplemented: podcast full-listening/player/media contract; genuine seek coverage; production inference/real contextual synonym quality; reverse paired-source vocabulary; physical devices/spoken VoiceOver; overnight/OS timezone-notification lifecycle. No publication is authorized by these local results.
