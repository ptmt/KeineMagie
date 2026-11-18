# Native Dictation — global system TabView accessory

This local candidate supersedes the **Dictation-only footer** decision in `DICTATION-NATIVE-CAMERA-PLAYER.md`. Base: `5dd8799d087d0e136db44e6f971f6c7d29915c1d`. No publication or production/account/provider operation is authorized or performed.

## Native presentation

- `MainTabsView` owns one `DictationPlaybackCoordinator` and the Dictation navigation path. All four tabs share it through the environment. No practice destination creates or owns a player.
- The root TabView uses Apple's `tabViewBottomAccessory`. Its Liquid Glass is supplied by the system, not a content rectangle or a blur/material replica. `tabViewBottomAccessoryPlacement` adapts the title/controls for inline placement; expanded placement includes real elapsed, remaining and nonseekable progress.
- Installed Xcode 27.2 SDK declarations and Apple's primary documentation agree: `tabViewBottomAccessory(content:)` and placement are available from iOS 26.0; the `isEnabled:` overload starts at 26.1. The 26.1+ path enables/disables the accessory without replacing the TabView. iOS 26.0 uses conditional accessory content. Existing iOS 17–18 deployment support retains a root-level standard bar fallback; those older runtimes are not claimed as Liquid Glass or as runtime-verified here.
- No accessory is shown for an empty selection or unprepared audio. Explicit Prepare remains in the practice content; pending preparation and cached selected audio enable the global bar. There is no autoplay or automatic preparation when selecting/opening an attempt.
- The title/body is a navigation button, separate from the 44pt transport button. Opening the bar selects Dictation and its exact saved attempt ID using the normal NavigationStack. It does not create an attempt, POST, start playback, replace the draft, or reset an already-open path.
- Tab changes, Back and destination disappearance do not stop playback or discard the admission/controller. The same clock keeps advancing on Translator, Podcasts and Coach. Actual OS/background interruptions still freeze the clock and expose explicit Continue, preserving the listening count.

Primary sources, fetched for this revision:
- https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)
- https://developer.apple.com/documentation/swiftui/tabviewbottomaccessoryplacement
- https://developer.apple.com/videos/play/wwdc2025/323/ (tab accessory / Music example, approximately 5:31–6:06)

## Ownership, policy and security

The coordinator reads the owner-scoped journal rather than retaining a view's record bindings. Playback ledgers merge into their exact record without replacing typed drafts. Replacing the selected attempt synchronously stops the old engine and releases the old reservation as **interrupted**, never completed/refunded. A held admission that returns after suspension is released without playing if no newer operation has taken over. Same-owner late 401s still revoke identity; generation/reset fences reject stale callbacks and hide private selection immediately.

Temporary `canWrite == false` during foreground identity validation is **not logout**. The bar/controller/position survive that check while transport is disabled. Only owner-generation/identity loss purges selection. This distinction is covered by both the AppModel/coordinator harness and actual background/foreground UI flow.

The four-start, no-user-pause/no-seek, continuous sentence/repeat/gap and explicit final-reading rules are unchanged. Timing still uses decoded cached audio plus the shared playback/gap clock. Selection and navigation never invoke audio preparation, AI, Check or a new-attempt POST.

The native podcast surfaces were inspected: this candidate has no embedded podcast AVPlayer/AVQueuePlayer/AVAudioPlayer/WKWebView audio engine to arbitrate. There is therefore one active native media engine, not an invented podcast playback product. A structural guard makes a future competing engine require explicit arbitration work.

Camera capture, recognition worker, edited preview, insertion fences and permission behavior remain unchanged. Normal Back dismisses the editor's focus; tapping an already-open bar does not rebuild its path. Camera and draft regression tests remain part of acceptance.

## Evidence boundary

Runtime evidence uses the existing normal and small simulators only, sequentially, with parallel testing/cloning disabled. The cached WAV is the existing generated eight-second PCM fixture; sentence/repeat timing includes the real three-second gap. These are actual SwiftUI/AVAudioPlayer screenshots, not rendered mockups or provider-generated speech. The macOS harness exercises the production AppModel, coordinator, API client, journal and playback controller with synthetic transport, substituting only the platform audio-output adapter; it is not substituted for real simulator playback acceptance.

## Verified local acceptance — 2026-11-18

Evidence root: `/Users/tinyserve/.hermes/cache/scratch/dictation-global-player`.

| Execution | Actual result | Evidence under that root |
| --- | --- | --- |
| Normal simulator Release UI | **28 passed, 0 failed, 0 skipped** | `normal-final.xcresult`, `normal-final-summary.json`, `normal-final-command.json` |
| Small simulator Release UI | **10 passed, 0 failed, 0 skipped** | `small-final.xcresult`, `small-final-summary.json`, `small-final-command.json` |
| Core XCTest | 88 executed, 0 failures; 2 fixture-dependent cases exercised separately below | `core-final.log` |
| Core Swift Testing | **82 passed** | `core-final.log` |
| Real Go Dictation admission/recovery/revocation bridge | **1 passed, 0 skipped** | `go-bridge.log` |
| Real Go podcast wire decoding | **6 passed, 0 skipped**, including the other fixture-dependent case | `podcast-wire.log` |
| Production AppModel/coordinator harness | **118 passed** | `native-ci-final.log` |
| Native CI checks | **62 passed** | `native-ci-final.log` |
| Actual Vision/camera worker | **6 PASS groups** | `camera-worker.log` |

The UI runs used Xcode 27.2 (27B52), iOS 27.2, Release, `-jobs 2`, `-parallel-testing-enabled NO`, and only the supplied normal `93E1113F-6736-4CCB-827D-0E2F1C3876EA` then small `56A70197-59DE-4410-9E76-25272244E9C8` devices. No simulator was created, cloned or deleted. Acceptance source hashes are retained in `source-manifest.json`. After the UI runs, changes were limited to documentation and removal of one trailing empty line from `DictationPlayer.swift`; the exact one-newline difference was verified and the final Release build passed (`release-final-build.log`). Local synthetic fixture batches were isolated before their history limit, with previous receipts preserved. The local fixture was stopped and both simulators shut down after acceptance, releasing the slot.

Coverage includes all-tab uninterrupted real playback, exact-attempt return and draft retention, separate transport activation from Translator, no extra listening reservation, actual background/Continue, owner logout, four-start exhaustion, continuous sentence/gap timing and explicit final reading, download/401 fences, camera preview/append/cancel, native Back/swipe, five locales, maximum Dynamic Type/keyboard geometry, and Translator/Coach/Podcast regressions. Production coordinator harness cases additionally cover held requests, replacement/late admission cleanup, same-owner revalidation and stale-owner callbacks. The initial cross-tab regression failed against the previous lifecycle (`red-live.xcresult`); the held-admission cleanup test also failed before its fix (`lease-red.log`). Historical failed runs are retained, not relabeled as passes.

### Inspected, unaltered runtime previews

All paths below are beneath the evidence root's `previews/`; `preview-manifest.json` maps readable filenames to their original xcresult attachments. Copies were SHA-256 checked against the original PNGs; no pixels were altered.

- `normal-global-Light-translator-playing.png`, `normal-global-Light-coach-playing.png`, `normal-global-Light-dictation-playing.png`: same `Player 6A13A8`, elapsed **0:01 → 0:06 → 0:09**, remaining **−0:18 → −0:13 → −0:10**, with the exact draft restored.
- `normal-global-Dark-translator-playing.png`, `normal-global-Dark-coach-playing.png`, `normal-global-Dark-dictation-playing.png`: same `Player 7FDAA6`, the same advancing clock sequence and preserved draft.
- `normal-global-Light-podcasts-playing.png`: same light sequence at **0:04 / −0:15**, above the Podcasts tab bar.
- `normal-global-reduce-transparency-coach.png` and `normal-system-reduce-transparency-enabled.png`: real OS setting enabled; legible native accessory. The test restores the prior system setting.
- `small-global-Dark-translator-playing.png`, `small-global-Light-coach-playing.png`: readable title/clock/independent controls on the narrow screen, above the native tabs.
- `normal-en-Dark-accessibility-keyboard.png`, `small-en-Dark-accessibility-keyboard.png`: complete large draft and caret remain above the actual keyboard. The native accessory/tab chrome hides for editing rather than becoming a second keyboard footer.

The protected original worktree's **304 manifest hashes match**. Camera/OCR source, catalog and fixture bytes match the base commit. AnyProgress was not modified. No production/provider activity occurred; Translator's unsynced-style message in these private-fixture screenshots is retained rather than visually concealed.

Physical iPhone capture/permissions/handwriting and spoken VoiceOver remain unverified. No TestFlight build, push, deployment or publication is included.
