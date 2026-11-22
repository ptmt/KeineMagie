# Web Coach composer: optical alignment

Base: `cb26b5f44bb27b7c0b01d9a6be3b958943536b76`. Isolated branch `fix/web-composer-alignment`; source candidate unchanged. Local synthetic APIs only; no production access, inference, deployment or push.

## Cause and minimal correction

The supplied crop was reproduced in the actual application. Both buttons and the one-line textarea already occupied equal 44px boxes. The textarea uses 16px system text, 24px line-height and 10px vertical padding; the plus uses a 26px glyph with line-height 1. Equal box centers therefore did **not** imply equal visible ink centers. Plus ink was 2.5px below the sampled Latin draft ink in light mode and 3px below it in dark mode.

Only `.coach-menu-trigger` internal padding changes from `0` to `0 0 4px`, lifting its glyph 2px inside the unchanged 44×44px control. No transform of the hit target, textarea movement, font change, new icon, shell change, send/Stop change or JS behavior change. Bottom alignment remains intentional for multiline text: plus follows the final line, not the middle of the expanded editor.

## Verification

- RED before production edit: actual browser screenshot ink regression failed for single/multiline in both widths/themes. Replayed original stylesheet later for matching complete viewport captures; `composer-alignment-evidence/red.log` and `before/receipt.json` retain the failure.
- GREEN Chromium and Playwright WebKit: desktop 1280×900, mobile-sized 390×844; light/dark; empty placeholder, `Discussion draft ä🙂`, three lines; plus-to-text ink-center difference ≤1px. WebKit is **not** Safari/iOS certification.
- Real application checks: 44×44 plus/send/Stop and identical send→Stop rectangle; textarea heights 44→92→140px, internal scroll at cap and shrink to 44px; focus, selection 2–6 and exact emoji draft preserved on menu Escape; menu opening sends nothing; real synthetic answer cancellation works.
- Existing menu browser regression passes five locales × two widths, keyboard/outside dismissal and action payloads. Existing parity browser passes its four viewport/theme variants. All 39 Coach Node tests pass. No page JS errors.
- Inspected actual before/after crop and full viewport screenshots, including mobile multiline, desktop light, mobile menu, dark Stop and WebKit dark/emoji. Pixel diff of all four matching single-line full viewports is confined to the plus glyph (14×16px bounding region); no surrounding UI changes.

## Evidence paths (relative to this document)

- Before crop: `composer-alignment-evidence/before/chromium-1280-light-single-crop.png`
- After crop: `composer-alignment-evidence/after/chromium-1280-light-single-crop.png`
- Before full viewport: `composer-alignment-evidence/before/chromium-1280-light-single-full.png`
- After full viewport: `composer-alignment-evidence/after/chromium-1280-light-single-full.png`
- Mobile dark multiline: `composer-alignment-evidence/after/chromium-390-dark-multiline-full.png`
- Menu / Stop: `composer-alignment-evidence/after/chromium-390-light-menu-full.png`, `composer-alignment-evidence/after/chromium-1280-dark-stop-full.png`
- WebKit: `composer-alignment-evidence/webkit/` (same state/width/theme naming).
- JSON measurements and logs: `composer-alignment-evidence/{before,after,webkit}/receipt.json` and `composer-alignment-evidence/*-green.log`.

## Reproduce

Python environment needs `playwright` and `pillow`; install Chromium/WebKit with Playwright as needed. Run from repository root:

```sh
COMPOSER_EVIDENCE="$PWD/docs/composer-alignment-evidence/after" python web/tests/coach_composer_alignment_browser.py
BROWSER=webkit COMPOSER_EVIDENCE="$PWD/docs/composer-alignment-evidence/webkit" python web/tests/coach_composer_alignment_browser.py
python web/tests/coach_menu_browser.py
python web/tests/coach_parity_browser.py
node --test web/tests/coach*.test.mjs
```

Optional `COMPOSER_BASELINE_CSS=/absolute/path/to/original-coach.css` replays the baseline stylesheet without touching the candidate. Its optical assertions should fail. Optical thresholds are scoped to the tested macOS system-font renderers, not proof of every OS/font/zoom combination. No native test matrix was needed for this CSS-only correction.
