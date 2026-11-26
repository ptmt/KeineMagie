# Web Coach composer — local candidate

Base: `a120d641165586eb9e5ceee0b624f7906e17da98` (unpublished podcast activity/star work preserved). Verified local `origin/main` at `9c386eddfb6cff1511b95c8182869ccc3c56db67` is an ancestor. Isolated branch `candidate/web-coach-composer`, worktree `/Users/tinyserve/Projects/KeineMagie-web-coach-composer`. No push, deployment, production requests, paid inference, native edits, or activity-control changes.

## Changes

- Only the main **web Coach discussion composer** sends on unmodified Enter, through its existing form submit/message route. The exact draft, owner, request identity and cancellation path remain in the existing state controller.
- Cmd+Enter replaces the selected range with a newline, puts the caret after it and dispatches an input event for sizing/button state. Shift+Enter retains the browser's natural newline. The 2000-character limit also applies to manual newline insertion.
- Composition lifecycle, `isComposing`, `keyCode === 229`, held-key repeats, Ctrl/Alt modifiers, empty/whitespace drafts, signed-out and busy/pending states cannot accidentally send. Enter during pending work cannot turn into Stop. Explicit Stop remains available, and editing the next draft remains possible.
- Send is disabled for empty/whitespace drafts. Successful sends clear only their unchanged draft. A late completion cannot steal menu/navigation focus or focus a composer from an earlier owner generation, including sign-out/sign-in to the same owner.
- Removed the nested black textarea focus outline. A restrained adaptive outer focus outline identifies the whole composer; individual buttons/menu items retain their keyboard focus. Forced colors use Highlight. Browsers without `:has` retain the original textarea focus fallback.
- Horizontal text padding increases from 4px to 8px; vertical padding, plus glyph's existing internal 2px optical lift, 44px plus/send targets, glass, bottom alignment, 140px growth cap and exercise-answer shortcuts are unchanged. No permanent shortcut-help paragraphs.

## Executed verification

All browser runs served the actual application with isolated loopback synthetic API responses. They do not certify production services, physical iOS/Safari keyboards, or an OS IME candidate window.

- TDD RED reproduced before the corresponding edits: Enter sent zero requests; Cmd+Enter left the selection unchanged; compositionstart without the event flag sent unexpectedly; empty Send was enabled; nested textarea outline remained; late owner/menu responses stole focus. These failures were followed by passing targeted reruns.
- `coach_composer_keyboard_browser.py`: Chromium and Playwright WebKit, each 1280×900 and 390×844, light/dark. Exact Enter payload/one send, both newline shortcuts, Unicode range replacement/caret, input events, maxlength, all IME guards (synthetic composition/key events), Ctrl/Alt, repeat/double Enter, empty whitespace, pending/Stop, next draft, menu Escape/caret, keyboard focus, growth 44→68→92→140 and shrink to 44, internal scroll at cap, five locale changes preserving draft/selection, no overflow or page JS errors.
- WebKit initially skipped the plus button on plain Tab under its macOS keyboard policy; the test uses Option+Tab / Option+Shift+Tab to include controls. No production tabindex workaround was added.
- Existing optical alignment suite: Chromium and WebKit, both widths/themes; placeholder, emoji, multiline, plus/text ink delta ≤1px, stable Send→Stop geometry, menu focus/caret and growth/shrink/cap all pass.
- Existing menu suite: five actions, exact payloads, five locales × two widths, keyboard/outside dismissal and draft/caret pass. Existing parity suite: all four viewport/theme variants pass.
- All Coach Node tests: **41 passed**. Full web Node baseline: **188 passed, 1 skipped, 0 failed**; candidate: **190 passed, 1 skipped, 0 failed**. The two additions cover late owner-generation and menu-focus/draft preservation.
- `node --check web/coach.mjs`, `git diff --check`, and added production-line security/conflict-marker scan passed. No independent reviewer was spawned in this delegated one-shot run; parent may review the narrow diff before integration.
- Inspected real baseline crop, final desktop-light full viewport and final mobile-dark WebKit full viewport: the inner black rounded rectangle is gone, the focus boundary follows the glass shell, padding is comfortable, and plus/send alignment remains intact.

## Actual previews and receipts

Relative to this document:

- Before: `composer-keyboard-evidence/before/chromium-1280-light-crop.png`
- After: `composer-keyboard-evidence/after-chromium/chromium-1280-light-crop.png`
- Desktop light full screen: `composer-keyboard-evidence/after-chromium/chromium-1280-light-full.png`
- Mobile dark full screen: `composer-keyboard-evidence/after-webkit/webkit-390-dark-full.png`
- Keyboard matrix receipts: `composer-keyboard-evidence/after-{chromium,webkit}/receipt.json`
- Optical measurements / states: `composer-keyboard-evidence/alignment-{chromium,webkit}/`

Baseline capture-only receipts contain no test verdicts; they are visual evidence, not acceptance runs. Full web Node logs are retained at `/Users/tinyserve/.hermes/cache/scratch/composer-{base,candidate}-node.log`.

## Reproduce

From the candidate root with Python Playwright/Pillow and installed Chromium/WebKit:

```sh
node --test web/tests/*.test.mjs
python web/tests/coach_composer_keyboard_browser.py
BROWSER=webkit python web/tests/coach_composer_keyboard_browser.py
python web/tests/coach_composer_alignment_browser.py
BROWSER=webkit python web/tests/coach_composer_alignment_browser.py
python web/tests/coach_menu_browser.py
python web/tests/coach_parity_browser.py
```

Set `TMPDIR` to the Hermes scratch directory and `COMPOSER_KEYBOARD_EVIDENCE` / `COMPOSER_EVIDENCE` to the desired evidence directory. Local tested interpreter: `/Users/tinyserve/.hermes/cache/scratch/composer-alignment-venv/bin/python`.
