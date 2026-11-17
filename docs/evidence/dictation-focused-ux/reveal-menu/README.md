# Show original in the existing attempt menu

Base: `5d78f7b1df1e448664a2d0ecb74898116a1e739b` (verified clean).

Moved the existing localized Show original button into the existing ellipsis
menu; no new menu or standalone reveal control. Confirmation, busy gating,
assistance tracking and checked-record local reveal are unchanged. The existing
behavior has no Hide original toggle: after revealing, the action disappears.
Return focus to the menu summary after reveal redraws. No hint, audio info icon,
Check placement, playback policy, CSS, backend or native changes.

Verification:
- RED: mounted Node assertion failed because Show original was outside the menu;
  GREEN after moving the same button.
- RED: Chromium revealed correctly but lost focus; GREEN after scoped focus return.
- `node --test web/tests/*.test.mjs`: 138/138 pass.
- `uv run --with playwright python web/tests/dictation_reveal_menu_browser.py`:
  10 cases (five locales × unchecked/checked), no page errors. Opening the menu
  performs no request and reveals nothing; Enter/Tab/Escape, canceled and accepted
  confirmation, busy disabling, draft preservation, playback adapter state,
  checked local reveal and 320/390/1280px overflow checks pass.
- `dictation_focused_browser.py`: full existing synthetic lifecycle passes.
- `dictation_headings_browser.py`: 20 locale/mode/policy cases pass.
- `dictation_correction_browser.py`: five locales and explicit keyboard Check pass.
- `git diff --check`: clean. Existing backend-dependent browser selectors updated
  to open the menu; those Go/Piper/cached-provider fixtures were not run.

Evidence uses actual Chromium with production module/CSS and explicitly synthetic
local API/media adapters, not production data or provider inference. Visually
inspected `ru-mobile-closed-menu.png` and `ru-mobile-open-menu.png`: standalone
reveal absent, translated menu item fits, original remains hidden on menu open.
Old evidence is retained unchanged. No push, deploy, Xcode or provider calls.
