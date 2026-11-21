# Translator continuous native canvas — approved release

Owner explicitly authorized publication after the preview. Native scope is frozen: one continuous semantic system-background canvas, source above output, quiet divider, compact direction in the top native header immediately left of Settings, and one inline Translator title. No further design approval is pending.

## Scope and preservation

- Isolated worktree `/Users/tinyserve/Projects/KeineMagie-translator-canvas`, branch `candidate/translator-continuous-canvas`, base `cacf2596cd66722d34e1f7c18baef9213df9c28f`.
- **Native iOS only. Web is unchanged**, as previously disclosed. The unrelated compact web Listen candidate `ba61d0ec` is not included. No server deployment is required or performed.
- Production changes are confined to `TranslatorView.swift`, `MainTabsView.swift`, and `TranslationShortcutsView.swift`. Existing Coach, Dictation manual timeline/hybrid assessment, media ownership, ledger, Core and AppModel remain unchanged.
- Explicit Translate, literal draft/output/copy, Clarify/Apply, durable outbox, GET-only uncertain recovery, owner fences, 90-second feature / 8-second authentication deadlines are preserved. Typing, language selection and opening Styles do not authorize inference.
- Styles retains its real editor/manager/conflict actions in a contextual native sheet. Foreground synchronization belongs to the translator, not the sheet lifecycle.
- No microphone/camera/OCR/folder/modes were added. No production ledger writes, historical-hold resets, identity bypasses, or live paid AI/TTS calls occurred. Historical budget state was not re-audited by this UI-only release.
- Original dirty workspaces verified hash-identical: KeineMagie **304/304**, AnyProgress (`Projects/anyring`) **13/13**, including unchanged HEAD/index/status. Generated projects, caches and credentials are not committed.

## Actual evidence

Durable machine receipts: `docs/evidence/translator-canvas/verification.json`. These files and PNGs actually exist. Direct runtime screenshots are unretouched synthetic samples, not translation-quality evidence.

The earlier `km_canvas_evidence.py` export had never executed. After the owner's explicit authorization, its contents were read and a normal guarded retry **executed successfully**. There is no pending export approval. Its pre-header screenshots and failures are explicitly historical in `historical-pre-header.json`; they are not final acceptance. Corrected-header runtime PNGs and the five prior readable xcresults are retained separately in `header-historical-receipts.json`: **25 executions passed, zero failures/skips**.

Earlier RED receipts include card-to-canvas, maximum-text editor/menu overflow and header placement failures. The final layout bounds the editor after the bottom action inset and gives the UIKit menu its proposed width. The follow-up test finishes native keyboard dismissal and recomputes scroll bounds; strict full-frame, Apply and retry assertions remain intact.

## Final exact-source local verification — November 21, 2026

A fresh Release build-for-testing was exercised serially with existing simulators, no clones/new devices/deletions:

| Device | Coherent final receipt | Result |
| --- | --- | --- |
| iPhone 17 `93E1113F-6736-4CCB-827D-0E2F1C3876EA` | `km-canvas-release/normal-final.xcresult` | **8 passed, 0 failed/skipped** |
| iPhone SE 3 `56A70197-59DE-4410-9E76-25272244E9C8` | `km-canvas-release/small-final.xcresult` | **6 passed, 0 failed/skipped** |

Scratch receipt root: `/Users/tinyserve/.hermes/cache/scratch/`. JSON contains exact test identities and final Swift source hashes. Normal gate covers five locales × ordinary/maximum text, direction/keyboard/draft/output retention, header/control bounds, canvas empty/filled/large keyboard and real policy-2 global-player Stop/draft/cross-tab behavior. SE gate covers the same canvas cases and real player flow plus both strict follow-up Apply/retry tests.

- Full native CI discovery: **66 tests**, zero failures, one pre-build effective-plist skip; post-build metadata **3/3 passed**, closing that prerequisite.
- Portable translator/navigation/global-player guards: **16 passed**.
- Unchanged Core receipt retained: **108 XCTest executed, 5 skipped, 0 failures**, plus **84 Swift Testing passed**.
- Actual AppModel lifecycle harness receipt retained: **123 passed** with injected adapters; external opt-in bridges are not claimed as live service verification.
- `git diff --check` passed. Existing audio-session main-thread runtime warnings remain recorded, not represented as fixed.

### Global-player gate: correct fixture and released policy

The old port-8799 fixture was absent and its old history contained 30 records; that directory was preserved. A new isolated store verified zero authenticated records, with a tracked fixture listener and no paid transport. This exposed a second, separate test-harness mismatch: legacy `DictationPlayerUITests` expect `dictation-prepare`, whereas the already-released policy-2 UI exposes `dictation-manual-transport`. Three legacy player tests failed before playback; their diagnostic xcresult is retained and is not counted as acceptance.

The existing `DictationManualUITests/testGlobalPolicyTwoStopAndDraftAcrossAllTabs` is the matching production-policy gate. Only its fixture-file path became configurable, preserving its default and every assertion. It ran against the unchanged real Go native integration fixture with fresh synthetic auth/storage and generated PCM; actual auth, HTTP, admission, playback and draft storage remain real. The test passed on both devices, proving clock advancement across tabs, one root player, exact attempt/draft return, explicit Stop reset and retained allowance. The fresh fixture ended with **2 records**; no production cap or identity policy was changed.

### Runtime inspection and cleanup

Real light/dark normal/SE captures show the continuous canvas and top language direction. Maximum-text last line/caret remains above Translate and keyboard; long output remains scrollable, not falsely claimed to fit the full screen. Fresh final xcresult PNG/AX exports are under `normal-canvas-attachments`, `small-canvas-attachments`, and `normal-player-attachments`. Earlier corrected-header previews are `header-*.png`.

Both borrowed simulators are shut down; the tracked fixture is stopped and port 8799 is closed. The shared local simulator slot is released before hosted CI. Old fixtures/results and unrelated worktrees are preserved.

## Publication status

Local gates are satisfied; publication is authorized. The exact pushed SHA, one `ios-testflight.yml` dispatch with `publish=UPLOAD`, validate/upload job IDs, archived marketing/build version and explicit Apple success marker will be recorded after actual upload. No upload is claimed at this checkpoint. Push validation does not itself upload, and the server workflow is path-filtered away from this native/docs-only change.

Simulator rendering/AX and synthetic transport do not establish physical-device behavior, spoken VoiceOver, real provider quality, Apple processing or tester availability.
