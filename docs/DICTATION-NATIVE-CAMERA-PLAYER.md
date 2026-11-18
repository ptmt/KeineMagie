# Native Dictation: navigation, compact transport and photograph answer

> Historical base-candidate report. The Dictation-only footer and off-tab interruption decisions below are superseded by [the global system TabView accessory](DICTATION-GLOBAL-PLAYER.md). Camera/OCR and native navigation remain unchanged; this report's original evidence is retained.

## Candidate scope

Local-only candidate on `candidate/dictation-native-camera-player`, based on verified `origin/main` `c0c6ff3be9194495e45abe921181b403da0c3542`, which includes release `78e2ebf589cbee9f574b497892319afa255de121`. No publication, server deployment, paid inference/TTS, signing-asset changes or real-account mutation is part of this change.

The user's requested changes are standard top Back/swipe-back, a compact bottom audio player with elapsed/remaining time, and a photograph → recognition → editable answer flow.

## Behavior and boundaries

- Dictation history pushes the selected practice into its own native `NavigationStack`. Back and edge-swipe are system navigation, not an inline History row or custom gesture. The selected draft is journaled while typing; back immediately exposes local attempts even if an existing save is pending. Returning to the tab does not clear/reload the current selection. Other tabs retain independent stacks and the system tab bar.
- The session-generation identity wraps the complete authenticated tab/stack group, not only a root view: owner changes remove pushed private destinations as well as their root data.
- A selected-attempt `safeAreaInset(edge: .bottom)` hosts compact Prepare/Play/Continue, speed and information controls. It is above the system tab bar/keyboard and disappears outside the selected Dictation practice. There is no pause button, seek gesture or slider. The four-start policy, explicit final reading and server admission remain authoritative.
- Apple documents `tabViewBottomAccessory(content:)` as iOS/iPadOS 26+. The app still supports iOS 17, so it deliberately uses the public safe-area API on the practice destination instead of availability-splitting the transport into a TabView accessory or using tab-bar introspection. This also confines the transport to the practice and its keyboard layout. Source: Apple's SwiftUI documentation JSON, recorded in local evidence as `apple-bottom-accessory.json`.
- Whole/final duration is decoded by `AVAudioPlayer` from the actual cached audio. Sentence/repeat progress sums decoded asset durations and the actual three-second inter-clip gaps; repeated assets count each occurrence. Missing/invalid duration stays unknown (`—`), not a text-length or bitrate estimate. Elapsed uses the media position and active gap clock. Interruptions freeze it; completed gaps remain counted during delayed admission. Duration metadata has its own cancellation generation so pressing Play cannot discard the remaining sequence duration.
- Time labels have localized accessibility descriptions; the decorative nonseekable progress is hidden from accessibility. No per-tick announcement is posted. Controls retain native 44pt-or-larger targets. The transport and camera/Check row cap typography at XXXL, while the answer retains full accessibility Dynamic Type. After keyboard presentation, the focused editor scrolls to its action header so both actions remain below system navigation and the typed fixture/caret stay above the footer. Acceptance checks both lower and upper bounds; it does not mistake an offscreen Check button for a valid layout.
- The camera button starts a user-initiated camera sheet. Apple Vision recognizes locally off the main actor, with orientation normalization, bounded input/image size and supported-language fallback. The editable preview inserts only when explicitly requested; append is default, replace requires its toggle. Owner/attempt/presentation/operation fences reject stale work. Insert uses the latest draft and rejects capacity overflow without truncation. No original answer, photo upload, Photos-library write, automatic Check or inference request is involved. Approved inserted text uses the ordinary draft-sync path.

Camera implementation and reproducible recognition harness: `native/DictationCamera-INTEGRATION.md` and `native/ci/test_dictation_camera.sh`.

## Verification receipts

Verified on 18 November 2026 with Xcode 27.2 (27B52), Release configuration, iOS 27.2, existing devices only and parallel simulator cloning disabled:

| Gate | Result |
| --- | --- |
| Final coherent normal-device UI, `normal-final-fresh.xcresult` | **38 passed, 0 failed, 0 skipped** |
| Final iPhone SE (3rd generation) UI, `small-final.xcresult` | **8 passed, 0 failed, 0 skipped** |
| Full Core XCTest | **87 executed, 2 fixture-gated skips, 0 failures** |
| Full Core Swift Testing | **82 passed** |
| Actual AppModel harness | **113 passed** |
| Full native CI discovery with built app plist | **59 passed** |
| Production-worker real Vision harness | **6 groups passed** |
| Actual Go Dictation bridge + podcast wire verifiers | **Both passed**, separately exercising the fixture-gated paths |

The final normal UI gate covers Dictation camera/player/policy/persistence, Coach/Daily, passage groups, profile synchronization/revocation, Translator result controls/copy/followup and initial geometry. The small gate repeats all new camera/player tests, five-locale controls, maximum accessibility keyboard geometry and profile conflict/offline recovery. Camera tests include editable recognition, default append, cancel, explicit replacement and simulator-unavailable handling. Player tests cover native back/swipe with draft preservation, real clock advancement/decreasing remaining, natural sequence completion, explicit final reading, interruption without another start, off-tab isolation and owner reset.

Machine-readable test identities, exact device IDs, counts, screenshot/WAV/app hashes and runtime warning messages: `docs/dictation-native-camera-player-receipts.json`. Core/CI/bridge/Vision logs and intermediate red/green results: `/Users/tinyserve/.hermes/cache/scratch/dictation-camera-player`. The checked-in WAV generator reproduces the exact runtime fixture byte-for-byte (SHA-256 `de0d54b330ecfd9cdea259dcc230ee14862ed31eafcffbb8c0d68f3d77b2e0d1`).

All seven retained PNGs were inspected, with no recreated or composited UI:
- `screenshots/dictation-native-camera-player/normal-light-ready.png`
- `screenshots/dictation-native-camera-player/normal-dark-ready.png`
- `screenshots/dictation-native-camera-player/normal-playing.png` — real `0:02` elapsed / `−0:06` remaining.
- `screenshots/dictation-native-camera-player/normal-ax-keyboard.png`
- `screenshots/dictation-native-camera-player/small-ax-keyboard.png`
- `screenshots/dictation-native-camera-player/small-keyboard.png`
- `screenshots/dictation-native-camera-player/small-camera-preview.png`

DE/EN/RU/ES/FR small-phone captures were also inspected in the exported small-suite attachments. The 304-file protected manifest of the owner's dirty main checkout remains byte-identical. The two shared simulators were shut down after acceptance, with no creation/cloning/deletion and no remaining Xcode build; the shared heavy-test slot is released.

Independent read-only source review found two timing races (duration load invalidated by admission; completed gap disappearing while the next admission awaited). New suspended-transport regressions reproduced both, including the resumed-gap case, before the fixes. Follow-up review reports no remaining actionable correctness/privacy findings in the inspected scope. It did not execute tests or inspect physical capture.

Runtime image inspection also exposed a false-positive maximum-type layout gate: Check was above the keyboard but hidden behind navigation. The strengthened gate failed on its real upper bound; the small-phone follow-up also caught a native 41.5pt button despite a 44pt outer frame. Header scrolling and native large control sizing fixed these without reducing the answer's accessibility font. A repeated integration attempt hit the real 30-item history cap because it reused synthetic storage after the small suite; that fixture was preserved, the production cap was not changed, and the final normal gate starts with verified-empty isolated storage.

## Deliberate limitations

The WAV used for clock acceptance is a generated eight-second PCM signal played by real `AVAudioPlayer`, not new TTS or a claim about voice quality. The camera simulator fixture feeds a generated printed German image through the real capture-result/Vision pipeline, not canned recognized text. It proves OCR and insertion transport, not handwriting accuracy or a real photograph.

Physical iPhone capture, OS permission denial/restriction, handwriting quality and spoken VoiceOver still require manual device checks. Simulator runs retain the pre-existing warning about synchronous `AVAudioSession` activation/deactivation on the main thread; those APIs were already used in the base and were not refactored here. No assertion failed in either final UI gate. There is no new TestFlight build or publication authorization.
