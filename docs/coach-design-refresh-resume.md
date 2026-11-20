# Coach design refresh — local preview verified

November 20, 2026. User explicitly approved the corrective batch; ordinary guarded patch/terminal tools succeeded. Local preview only: no push, release, provider call or publication. Base remains `7b87555bc6dd0080b87bfceefaffe26245fd553a` (documentation; released product `a6699b0`) on `candidate/coach-design-refresh`.

## Final coherent acceptance

Artifacts: `/Users/tinyserve/.hermes/cache/scratch/coach-design-refresh/`. Final sources are identical across both runs:

- `small-verified.xcresult`: **29 passed, 0 failed, 0 skipped**, iPhone SE 3, explicit light appearance.
- `normal-verified.xcresult`: **29 passed, 0 failed, 0 skipped**, iPhone 17, explicit dark appearance.
- Each includes all CoachUITests, CoachPresentationUITests, CoachDailyCandidateUITests, and three real-WAV global-player regressions: all-tab playback/exact-attempt return, cross-tab explicit Stop/reset, and native Back/swipe/draft restoration. Player tests also explicitly exercise Light and Dark.
- Five locales: en/de/ru/es/fr feedback, maximum Dynamic Type contextual actions and history; keyboard, manual history, own-send follow, empty/daily entry, answer error, active/filled/correct/incorrect/checking, normal/reduced-motion states. Exactly one accessible Checking plus actual visible localized text is asserted in the assessment flow.
- Final Go Coach run: **38 test pass events, 2 skips, 0 failures** (`server-coach-final.jsonl`).
- Earlier unchanged-model receipts remain valid: Core 100 XCTest cases with 4 skips/0 failures plus 84 Swift Testing passes; AppModel Coach/daily 16 passes; lifecycle 119 passes; two-client verification succeeds (including another 119-test lifecycle run). Logs retained in scratch.

Source SHA-256:
- `native/App/CoachView.swift`: `7338de2b4a0120b2262323ca327b4b9aecd9c8fb9e74fdc531a5c3864a00a8bd`
- `native/UITests/CoachUITests.swift`: `b5266b50e7c0383aa1c5984ddddbe63f4702b9cab7193de9f17d5a9db598e535`

## What changed

Presentation only: sentence-first exercise, quiet instruction, rounded native answer, compact 44pt Check separated from Skip, neutral bubble, contextual chips, integrated rounded native composer, quiet Earlier divider. No assessment/routing/daily-once/AI/haptics/backend/player changes.

Actual answer FocusState binds to its turn ID. Viewport shrink and settled native keyboard presentation follow an explicit marker below that answer's actions, not the whole ForEach child. Composer/manual-history behavior remains unchanged; session generation clears the focus owner. Native answer editing retains >=44pt height with reduced vertical inset.

Maximum-type chips and Check/Skip use intrinsic labels rather than syllabic wrapping or tiny fonts. Native Russian Message remains a real TextField placeholder. A fixed 44pt icon-only send target and adaptive horizontal spacing reserve its full width without shrinking text or painting a manual placeholder.

Checking displays real localized Text beside an AX-hidden spinner/static dots. Removing the combined accessibility wrapper prevents duplicate status descendants.

Only simulator fixture flags add deterministic empty/delayed entry and answer-error capture; synthetic content is explicitly labeled. The pending assessment fixture returns only `bei`, not a full corrected sentence; no answer content was invented. Global playback uses the real Go handler with locally generated 8-second WAV, never live AI/TTS.

## RED provenance and diagnostics

- Original `red.xcresult` and `red-dark.xcresult`: compact-design regression failed against released source; baseline screenshots retained.
- Previous `normal-final`: 22/22; `small-final`: 19/23, failing keyboard Check, populated chat, largest German chip wrapping, and largest history hit testing. Superseded, not final acceptance.
- `checking-red`: visible-text failure; subsequent `small-coherent` was 25/26 due to two accessible Checking descendants. `checking-single-green`: 1/1 after removing the combine wrapper.
- `placeholder-red`: actual field 245pt versus required 285pt; `placeholder-green`: 1/1, full Russian text visually inspected.
- Critically, an intermediate `small-final-pass` was 29/29 but its PNG still showed Check mostly under the inset. The test was strengthened to require the entire Check/Skip frame above contextual controls. `keyboard-full-red` failed at maxY 332 > 297. A keyboard-settled notification alone still failed (`keyboard-full-green`, despite its historical filename). An explicit bottom marker fixed the target geometry: `keyboard-full-green2` 1/1, then the final coherent 29/29 runs above. Do not use intermediate screenshots as final previews.
- One foreground test command hit the tool's 420-second wall, leaving incomplete `small-accepted.xcresult`; a normal intermediate run was intentionally stopped after visual inspection exposed the insufficient keyboard assertion. Neither is counted as acceptance. Final runs used tracked background processes and completed normally.

## Inspected preview files

Under `docs/evidence/coach-design-refresh/`:
1. `normal-verified-shots/coach-design-active-before-or-after.png` — normal dark active.
2. `small-verified-shots/coach-design-filled-keyboard-before-or-after.png` — small light keyboard, full Check and Skip visible.
3. `small-verified-shots/coach-russian-native-placeholder-largest.png` — maximum Russian type, full native Message placeholder.

The `*-verified-shots` files are byte-for-byte exported runtime attachments; manifests map the exported source attachments to their readable names. Final summary JSONs accompany the images. Historical groups remain only as diagnostic provenance.

## Limits and cleanup

This is simulator evidence, not physical-iPhone or spoken VoiceOver acceptance. At maximum Dynamic Type on the small phone, the whole exercise cannot fit beside the persistent composer and keyboard: upper content is intentionally scrollable/offscreen, not promised universally visible. Chips and composer text remain full size; native placeholders were inspected. Do not claim universal zero clipping from AX hittability.

Existing unrelated XCTest actor-isolation warnings and DictationPlayer main-thread activation runtime warnings remain; no behavior was changed to silence them. No web implementation or runtime review is included. This local preview still needs user visual approval before any publication.

Borrowed devices are reused serially, never cloned/deleted, and shut down after evidence export. Owned local fixture servers are stopped and temporary fixture credentials removed. Protected originals were rechecked: KeineMagie 304/304 and AnyProgress 13/13 hashes unchanged. Remote main remains `7b87555`; no push occurred.
