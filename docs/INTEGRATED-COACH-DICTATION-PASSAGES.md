# Integrated Coach, Dictation, Translator and passage groups

## Local repair scope — November 17, 2026

Branch `integration/coach-dictation-passages-local` in the dedicated integration worktree. No push, deployment, upload, real provider/AI/TTS call, or edit to any sibling worktree is authorized by this report. Parent review is required before release.

The inherited local history contained unresolved conflict markers committed in `native/App/Localizable.xcstrings`; the cherry-pick of `6103675` was separately paused on `SimulatorSessionFixture.swift`. The initial catalog parse failed at line 4, and the fixture failed `git diff --check`. These are actual reproduced failures, not inferred failures.

### Semantic repair

The entire 13,843-line damaged catalog was read through paginated `read_file` before editing. Recomputed a recursive three-way JSON merge from the actual git objects `3562cc9^` (405 keys), `6d2b563` (406 keys) and `3562cc9` (408 keys). There were no conflicting semantic leaves. The repaired catalog has **409 keys**, exactly the union, with every existing Coach/Daily/Translator/Dictation key and locale retained and the three passage keys added. Duplicate-key detection and equality against the computed merge were checked. No entire-side resolution was used.

The fixture retains both the Translator history-controls response and the real loopback passage transport as independent mode branches. Existing cache namespaces, Coach daily fixtures and translation followup fixtures are retained. The owning NavigationStack generation reset from `6103675` is retained; `7a550b1` is documentation-only, not the source of that privacy fix.

Source diff review against `6d2b563` confirms passage changes in AppModel are additive and reset-scoped. Daily admission/claims and Translator pairing/outbox code are not replaced. Coach group generation and assessment capture transcript plus relationships within the same source/learning transaction. Group GET reauthorizes inside the nested locks before reconciliation. Native already-canceled writes and same-generation superseded-read 401 handling remain intact.

## Verification evidence

Task-owned evidence directory: `/Users/tinyserve/.hermes/cache/scratch/km-integration-repair-evidence/`. All counts below must come from this integration's actual logs/results; the older committed passage screenshots are standalone source evidence, not combined acceptance.

| Gate | Fresh combined-tree result |
| --- | --- |
| Full `go test ./... -race -count=1 -timeout=240s` | Passed; server package 211.119 s |
| `go vet ./...` | Passed |
| Focused `TestDailyEntry` race JSON run | 16 top-level tests, 29 passing records including subtests |
| Node web tests + Dictation onboarding | 135 passed, zero failures/skips |
| Swift Core | 64 XCTest executions, one dedicated-wire skip, zero failures; 72 Swift Testing tests passed |
| Actual production AppModel harness | 106 Swift Testing tests passed |
| Daily AppModel harness | 16 passed |
| Actual Go podcast JSON → Swift wire | Six tests passed, including the dedicated test skipped in generic Core invocation |
| Actual Go Coach JSON → Swift wire | Runner passed |
| Two independent AppModels / race-enabled Go bridge | 106-test harness passed, Go bridge passed |
| Full Python native CI | Final run: 54 tests passed, zero skips, including the actual Release app's processed Info.plist; embedded 106-test harness passed |
| Chromium real episode tabs | Ten locale/width cases passed; keyboard/history/search/AX, 2,113 segments and zero AI POSTs |
| Chromium mixed-version, lifecycle, owner suites | All three passed |
| Chromium translation followups | 37 checks passed |

The Python failure expected the obsolete tabs-only `.id` placement. It was corrected to locate the closing brace of the owning NavigationStack and require its generation modifier. The revised test was separately checked against the old source and fails there; no production privacy fence was weakened. Its initial failure remains in `python.log`, successful rerun in `python-green.log`.

### Final native Release acceptance — passed

The final **single combined invocation passed 21 tests, zero failures and zero skips**, with `xcodebuild` exit 0 and the real Go fixture exit 0. This includes every original selected acceptance test plus the new Dictation refresh regression. The authoritative bundle is `km-integration-repair-evidence/final-combined/combined.xcresult`, not the earlier failed exploratory runs. It built and ran the actual Release simulator app; no startup-only or zero-test success is counted.

Covered together on the owned small iPhone SE:

- Coach check/skip targets, success and keyboard layout, normal/reduced-motion checking intervals, old-message position, background admission/draft retention, five-locale compact feedback. The separate Daily harness verifies foreground-only haptic events and silent cached feedback; this is not a physical-haptics claim.
- Dictation empty onboarding, primary creation and saved-form restoration, and **two real pull gestures** changing the synthetic API history to read 2 then read 3. The fixture returns no audio and makes no TTS call.
- Translator source/result footers, clear preserving the accepted result, clearing during pending work without discarding its outbox snapshot, exact Unicode clipboard results in five locales, independently opening both history records, paired followup preview/apply, large-font history controls, and unchanged source geometry during provider settlement, keyboard presentation and actual tab navigation.
- Passage groups through the real loopback Go API with 2,113 unchanged original segments: actual swipe save/unsave, adjacent/bridge/split/nonadjacent groups, last original index/citation, count semantics, cold online/offline owner cache, failed writes retaining confirmed stars, owner replacement, and authenticated 401 purging a **pushed reader**. Five locales also exercise XXXL swipes and context-menu compatibility.

#### Test corrections, not weakened product guarantees

Earlier results are retained in scratch: the first combined run passed 19/20, exposing a keyboard-covered tab-bar tap in the geometry test. XCTest could discover stale tab AX elements but typed characters instead of navigating. The test now dismisses the actual keyboard, asserts the Coach destination, and checks the exact unchanged draft before/after navigation. The new Dictation test initially swiped inert empty List space; it now pulls slowly from the actual row and requires changed history twice. Screenshot review also exposed overscrolled large-type captures, so tests now require the complete target below navigation and above the keyboard/tab bar. An exploratory extra 8-point tab-bar margin was stricter than the native bottom inset; the final assertion requires actual non-overlap, while retaining an 8-point keyboard gap. All corrected tests passed again in the final 21-test invocation.

The production Dictation and Translator views were not changed to satisfy these tests. Earlier failed bundles remain separate and are not relabeled successful.

#### Durable evidence and visual review

`docs/evidence/integrated-coach-dictation-passages/` contains the actual xcresult summary/test tree/command, gate-log excerpts and hashes, initial gate outcomes (including the original Python failure), browser outcomes, final synthetic Go state, and **30 unmodified native PNGs plus three actual browser PNGs**. Native exports are 750×1334; their source attachment names, test identifiers and SHA-256 hashes are in `native-screenshot-manifest.json`. The final bundle exported 99 PNG attachments in total. Inspection contact sheets are scratch-only derivatives, not substitutes for the preserved original images.

Inspected DE/EN/RU/ES/FR Coach feedback, Translator footer/history controls and passage swipes, plus Russian large type, keyboard layouts, Dictation onboarding/refreshed history, failed-write state, 401 purge, and followup pairing. The simulator was explicitly dark: inherited attachment suffixes saying `light` do **not** prove light-mode coverage; durable result images are named `dark`. At XXXL, long navigation/search-placeholder strings can truncate on this small screen; this existing layout is visible in the evidence and was not cosmetically redesigned. The selected action controls remain visible and exercised. Browser review includes a horizontally scrolling narrow tab strip, desktop summary and mobile followup.

Two existing runtime warnings report main-thread AVAudioSession deactivation in `DictationPlayer.stop()`; they are recorded in the xcresult summary, not hidden. No real AI/TTS, production account, real-device tactile behavior, archive/upload, deployment, or release was exercised. **Local integration is ready for parent review; this is not release approval.**

## Isolation

Initial and final read-only comparisons verified all **304 saved file hashes** and the exact expanded porcelain status from `/Users/tinyserve/.hermes/cache/scratch/keinemagie-preintegration-dirty.json`. The original worktree was not modified. No other worktree or AnyProgress visual candidate is part of this repair.

One newly created, task-owned iPhone SE (3rd generation) simulator was used: `2EE207BC-1449-4CF9-B0E3-439F59B487F8`. Release used one exact destination, two build jobs, and disabled parallel testing. The owned simulator is now verified **Shutdown**, and the loopback fixture exited successfully with no listener remaining on port 18879. No unrelated simulator was shut down. Cherry-pick state is cleared. Final verification scanned all **650 tracked files** with zero conflict markers, parsed all **22 tracked JSON/catalog files** with duplicate-key rejection, and passed both staged and full-baseline `git diff --check`.
