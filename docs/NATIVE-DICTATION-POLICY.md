# Native Dictation policy and focused practice integration

## Candidate and boundaries

This candidate is based on `072476f6201d5238e69c08158a73134a91c93b64` (all approved web through `37bfd038`, translation profiles, Coach/Daily and passage groups). It lives only in `/Users/tinyserve/Projects/KeineMagie-native-dictation-final`, branch `integration/native-dictation-final`. Native implementation `6a8902d` was cherry-picked as `83807d0`; the onboarding/history-confirmation conflict was merged semantically. No other worktree was edited and nothing was pushed or published by this worker.

Server and web files are unchanged from the integrated base. Native reuses the existing opt-in `playback_policy_version: 1` protocol, not a second client quota. Existing pending create/attempt bytes remain unchanged on retry; newly reserved operations opt in durably. Pre-policy attempts remain compatible. Do not roll the policy-aware backend back to an older struct-rewriting backend that drops persisted unknown fields.

## Implementation

- New Codable playback/listen/request types retain policy fields in native cache round trips. The authenticated playback route uses the existing API transport and an eight-second timeout.
- The owner/attempt-scoped controller refreshes authoritative state before admission, resumes the existing reservation, serializes fence-changing acknowledgements, renews leases, and stops media before lease expiry. Canceled, interrupted, decode-failed and stale callbacks never send successful `ended`.
- Background, audio interruption, route change and media-services-reset paths suspend without refunding admitted starts. Late 401s revoke the captured owner even after navigation, but cannot revoke a replacement owner.
- The independent ledger revision survives dirty draft refresh, stale UI updates, cold restore and explicit Use server conflict resolution. Draft-revision conflicts cannot rewind a newer four-start ledger.
- Explicit Prepare caches the required unique assets. Listening only retrieves cached audio. Sentence/chunk steps and repeats run continuously with real three-second gaps; final whole-text reading waits for a separate explicit tap and uses the same allowance.
- The practice surface follows approved web hierarchy while retaining native navigation: existing ellipsis, compact mode selector, untitled rules, state-driven audio action beside speed/info, Check at the draft's top-right, blank draft with no placeholder. No visible paid line, About-audio heading, hint heading or Pause control. Original is not auto-revealed; the existing ellipsis preserves confirmation/assistance and checked semantics.
- All 417 existing localization entries are semantically unchanged; 33 additive entries produce a 450-key catalog with five-locale rules/status/details. AppModel, profile synchronization, Coach/Daily and passage implementations remain untouched.

Shared merge seams are `DictationView.swift`, `Dictation.swift`, `DictationDraftStore.swift`, `Podcasts.swift`, `Localizable.xcstrings`, and a three-line simulator-only appearance modifier in `KeineMagieApp.swift`. New implementation resides primarily in `DictationPlayback.swift`, `DictationPlaybackController.swift`, and `DictationPracticeComponents.swift`. `SimulatorAppearance.swift` is fixture-gated and excluded from device builds; ordinary launches retain system appearance.

## Verification and evidence

Final coherent Release UI gate: **in progress; not yet accepted**.

Scratch evidence root: `/Users/tinyserve/.hermes/cache/scratch/dictation-final/`. The final command/result bundle is `coherent-command.json` / `coherent-release-final.xcresult`. One isolated iPhone 17 simulator (`93E1113F-6736-4CCB-827D-0E2F1C3876EA`, iOS 27.2), two build jobs, parallel testing disabled. No other simulator is controlled.

Completed non-UI checks:

- Full Go race suite: 562 passing and 15 explicitly skipped test records, zero failures; `go vet ./...` passed.
- Swift Core final suite: 78 XCTest cases including two opt-in skips, plus 79 Swift Testing cases; no failures. Dedicated actual-Go bridge and podcast wire paths run separately rather than counting generic skips as passes.
- Actual AppModel harness: 113 cases passed. Native Python discovery with the actual Release Info.plist: 58 tests passed before the final conflict-ledger patch; final-tree rerun is tracked separately.
- Source/localization guardrails, parser and `git diff --check` are not claimed as pixel or interaction proof.

## Findings retained rather than relabeled

- The parent's earlier `final-ui-exit.json` is exit 65. Its exact failing identity is `TranslationProfileSyncUITests/testMigrationConflictOfflineRelaunchAndRemoteDeletion()`: 23 passed, one failed. The separate corrected 1/1 was not a coherent 24/24 run. This candidate selects that full inherited suite again, plus all five Dictation lifecycle tests and new policy UI cases.
- First native policy probe passed 2/2 but exported images proved that `-AppleInterfaceStyle Dark` still rendered light. Those attachments are not dark-mode evidence. Added an explicit simulator-only fixture appearance override; the next exported Russian images were inspected and actually dark.
- The expanded sentence probe failed because its test entered sentence mode first but expected a whole-text start. The server correctly starts sentence mode at its sentence cursor. The corrected test explicitly listens to a whole text before changing modes, then requires the continuous sequence to stop before a separately requested final reading. No production protocol was changed to satisfy the mistaken expectation.
- Review found a saved conflict snapshot could rewind the local playback ledger through Use server. A new cold-restore regression failed first, then passed after preserving the latest ledger during conflict resolution. An initial coherent invocation was interrupted before completion to include this fix; it is not counted as acceptance.
- The Go bridge test initially waited only for `active == nil`, which publishes before the controller clears its busy flag. Under concurrent build load it issued subsequent Play calls too early. It now waits for the acknowledged ledger **and** idle controller and asserts both; the server's four-start/fifth-denial assertions are retained.
- Xcode reports the inherited warning about synchronous AVAudioSession activation/deactivation on the main thread. This work does not claim that warning resolved.

## Provider and release safety

No live provider tests or new paid generation were performed. Native audio acceptance uses only the already-authorized exact-source `Heute scheint die Sonne.` WAV through the existing test-only cache injector. The application USD 10 ceiling, private persistent acceptance hold and one-shot marker are untouched. The fixture extends only its test lifetime through a scratch Go overlay; production protocol/authentication/limits are unchanged.

Parent review of the final candidate is mandatory before any push/release. Full UI result, exported inspected screenshots, final source/evidence SHA and simulator cleanup must be recorded before this gate is called complete.
