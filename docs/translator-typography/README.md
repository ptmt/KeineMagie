# Translator placeholder typography — local Release verification

Base: `9c386eddfb6cff1511b95c8182869ccc3c56db67` (fetched `origin/main`, containing published `3498ad73168f11e9d3bf172a5011d62018f939d1`). Worktree: `/Users/tinyserve/Projects/KeineMagie-translator-placeholder-font`, branch `fix/translator-placeholder-font`. The original dirty worktree was not edited. Local integration candidate only; no push, deployment, Apple upload, production mutation or paid inference.

## Fix

The real input used native `TextEditor` with `.title3`; its empty-state overlay was SwiftUI `Text` inheriting body typography, positioned with approximate padding. The supplied screenshot and actual Release empty/typed comparison reproduced the mismatch. Merely adding `.title3` to `Text` was insufficient: ordinary-size glyph overlap remained 0.797 because the two native layout paths did not align exactly.

The overlay now uses a constant, localized `TextEditor` with the same `.title3`, transparent scroll background, native text-container layout, trailing 44pt lane and outer 8pt padding as the real editor. It remains hidden from accessibility and hit testing; it is never bound to the draft. Only its foreground color is secondary. The real editable view, binding, focus, editor height, clear button, canvas, direction header, selection/caret and keyboard handlers are unchanged.

## TDD and actual UI

`native/UITests/TranslatorTypographyUITests.swift` compares actual pixels for the exact phrase **Text to translate**, not an inferred font declaration. It normalizes grayscale contrast independently to ignore semantic text color, compares the full native editor rectangle and requires glyph intersection-over-union above 0.90. No shifted/aligned image matching is used: baseline, insets and wrapping must already coincide.

The comparison uses keyboard-dismissed screenshots. On SE at maximum Dynamic Type, normal caret-following scrolls typed text upward inside the short keyboard viewport; comparing that scrolled state with the empty prompt would be invalid. Separate focused captures and geometry assertions retain keyboard/caret coverage. The test also verifies empty draft values, typing/deletion, clear/focus restoration and cold-relaunch draft retention. A separate real double-tap selection test replaces only `Text` with `Words`, proving native selection and replacement.

| Release device (iOS 27.2) | Appearance | Baseline typography | Final suite |
|---|---|---|---|
| iPhone 17, `93E1113F-6736-4CCB-827D-0E2F1C3876EA` | light | both sizes fail | 7/7 pass |
| same | dark | both sizes fail | 7/7 pass |
| iPhone SE 3, `56A70197-59DE-4410-9E76-25272244E9C8` | light | both sizes fail | 7/7 pass |
| same | dark | both sizes fail | 7/7 pass |

Final matrix: **28 passed, 0 failed**. Each configuration includes the three typography/selection tests, all three `TranslatorCanvasUITests`, and `CompactTranslatorUITests/testHeaderDirectionAllChoicesKeepsKeyboardDraft`. Normal and maximum Accessibility XXXL are tested in each appearance. Baseline differential: **8 intended typography failures**, 4 selection passes, using unchanged production source and the final test harness. Glyph overlap rises from 0.138–0.260 to **1.000 at normal size**, **0.993 at maximum accessibility size**. Exact receipts are in `glyph-receipts.json`.

Additional checks: after restoring the candidate from the baseline differential, a fresh Release rebuild reran the three typography/selection tests (3/3 pass). `python3 -m unittest discover -s native/ci -p 'test_translator*.py'` (7 pass), same command with `test_localization.py` (8 pass), and `git diff --check` pass.

## Evidence

- `comparison-normal-light.jpg`, `comparison-normal-dark.jpg`, `comparison-SE-light.jpg`, `comparison-SE-dark.jpg`: inspected contact sheets of actual screenshots. Columns: baseline empty, baseline typed, candidate empty, candidate typed. Rows: normal and maximum Dynamic Type.
- `keyboard-selection.jpg`: inspected actual keyboard, selection handles and maximum-text SE editing. Native caret remains above Translate and the keyboard.
- `screenshots/`: 56 original, unaltered simulator PNGs, including focused/unfocused, selection and large-keyboard captures.
- `baseline-*-summary.json`, `final-SE-*-summary.json`, `final2-normal-*-summary.json`: xcresult summaries.
- Full xcresults/logs/attachments: `/Users/tinyserve/.hermes/cache/scratch/translator-typography/` (scratch, not a durable artifact).

All four comparison sheets were inspected: candidate placeholder and typed words match size, weight, line breaks and position; continuous canvas, divider and top direction are unchanged. Actual light/dark appearance is visible in the evidence, not inferred from launch arguments.

## Reproduce

Generate with `xcodegen generate` in `native`, boot exactly one approved simulator and set its appearance with `xcrun simctl ui <UDID> appearance light` (or dark), then:

```sh
xcodebuild -quiet -project KeineMagie.xcodeproj -scheme KeineMagie \
  -configuration Release -destination 'platform=iOS Simulator,id=<UDID>' \
  -derivedDataPath <scratch-build> -resultBundlePath <new-result.xcresult> \
  -parallel-testing-enabled NO \
  -only-testing:KeineMagieUITests/TranslatorTypographyUITests \
  -only-testing:KeineMagieUITests/TranslatorCanvasUITests \
  -only-testing:KeineMagieUITests/CompactTranslatorUITests/testHeaderDirectionAllChoicesKeepsKeyboardDraft \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test
```

Use the explicit synthetic `valid`/`translation-controls` fixtures already selected by tests. No real account or AI service is used. Devices were reused sequentially, not cloned or deleted, appearance restored to light, and both shut down afterward.

## Limits and harness corrections

An initial keyboard-arrow `typeText` experiment inserted the arrow literally; it was corrected to native double-tap selection plus deletion/insertion before final acceptance. A long combined matrix call hit the tool's 420-second limit after both SE gates; normal-device gates were explicitly rerun to completion. Neither interruption nor partial run is counted as passing. Existing unrelated Swift actor warnings and a `DictationPlayer.swift` audio-session main-thread runtime warning remain; no unrelated code was changed. Physical-device keyboard/VoiceOver behavior and release publication are outside this local candidate's scope.
