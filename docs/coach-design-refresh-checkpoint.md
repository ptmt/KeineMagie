# Coach visual refresh — pre-simulator checkpoint

Status: historical pre-simulator checkpoint, retained for provenance only. Subsequent acceptance and remaining limits are recorded in `coach-design-refresh-resume.md`. No push or release is authorized.

## Baseline

- Fresh `git fetch origin` resolves `origin/main` to `7b87555` (delivery documentation), with product commit `a6699b0` immediately below.
- Isolated worktree: `/Users/tinyserve/Projects/KeineMagie-coach-design-refresh`, branch `candidate/coach-design-refresh`.
- Supplied screenshot inspected: `/Users/tinyserve/.hermes/cache/documents/native-inputs/2582096f82d8055585b592575e97865e56569b4b47b303d1b7b45ff81fd00c31/img_3545495a9324.jpg`.
- Observed screenshot: instruction dominates sentence; redundant Awaiting answer; black rectangular answer field; oversized Check beside bare Skip; Hint/My progress links rather than chips; separate trailing send; Earlier is a floating tinted link. This is screenshot evidence, not fresh fixture-runtime evidence.
- Existing native routing separates answer (explicit immutable turn ID) from message draft. Keep this distinction and all model ownership/cache/receipt behavior untouched.

## Prepared regression

`CoachUITests.testChatDesignCompactAnswerControls` captures active/filled-keyboard/correct states and asserts: no redundant awaiting label while editable, answer/check/skip >=44pt targets, Check <=52pt, separated trailing Skip, unique contextual actions, disabled empty Check, explicit answer route and separate discussion label. It has not run; RED is not yet established.

Existing `swift test --package-path native/Core --filter Coach`: **22 tests passed, zero failures**. This verifies current Core baseline, not the design, iOS compilation, or full lifecycle suite.

## Next authorized slot

1. Reuse normal `93E1113F-6736-4CCB-827D-0E2F1C3876EA` and small `56A70197-59DE-4410-9E76-25272244E9C8`, serially and without cloning. Obtain explicit release confirmation before Xcode/simulator work.
2. Run regression against unchanged production source; export and physically inspect real fixture baseline before editing.
3. Keep changes primarily in CoachView: sentence-first hierarchy; quiet useful instruction; integrated rounded answer field; compact Check and separated trailing Skip; neutral exercise bubble with localized status accents; chips above rounded message composer; quiet Earlier divider. Preserve native toolbar behavior rather than faking glass.
4. Promote only actual returned correction content; do not reconstruct a purported AI correction from the source quote. Existing assessment fixture returns corrected_answer `bei`, not a complete sentence.
5. Existing five-locale history UI test currently asserts visible Awaiting answer and will need to assert the answer affordance instead once RED is recorded. Preserve history-bottom/manual-reading tests.
6. Exercise normal/small, light/dark, five locales, Dynamic Type and keyboard, empty/daily-loading/active/filled/checking/correct/incorrect/error/earlier states. Run full Coach lifecycle and owner/cache regressions; retain global Dictation player and all transport untouched.
7. Export inspected before/after screenshots and exact test receipts, local commit only, request user preview approval before publication.

## Web parity (source-only review)

`web/coach.css` has the same hierarchy risks: transparent borderless quick actions, whole-bubble green/red feedback fills, and a separate grid composer. Web needs a matching small presentation follow-up if parity is requested. No web file changed, no browser runtime review claimed, and no deployment authorized.
