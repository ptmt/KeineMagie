# Web redesign verification

Scope: web client plus exact static asset allowlist/Docker copy only. Native SwiftUI is reviewed separately in `native/NATIVE-DESIGN-REVIEW.md`. Verification uses synthetic fixtures/public guest access, never owner cookies or paid inference. Release status is recorded below after exact-commit deployment.

## Implemented
- Neutral light/dark palette; semantic green only for the connected indicator. Compact 44px primary, outlined/quiet secondary actions, neutral readable disabled states and keyboard focus.
- Guest Apple invitation above translator input, shorter mobile guest preview; primary visible at 320/390×844. Official localized Apple images unchanged.
- Four section links retained. Dictation/Coach expose unavailable badges and aria-disabled before activation; old fragment bookmarks retain honest unavailable pages.
- No decorative arrow on Translate in any of five locales.
- CSP-compatible blocking critical-copy bootstrap resolves document language before body parsing, applies critical static labels during parsing, disconnects at DOMContentLoaded; no whole-app hiding. Core/i18n modulepreload; episode code dynamically imported only on job routes.
- Same-owner session/provider notifications retain prompt editing and unchanged style nodes. Owner changes still clear private data.
- Keyed incremental podcast lists and incremental reader updates retain live input/details DOM. Quote forms created only on expansion; transcript starts with 100 rows, Show more adds 100, distant citation expands through its target.
- Job detail/resolve available independently of subscriptions context. Learning resources settle as a coherent snapshot with independent success/error states and retained prior values.

## Verified
- `node --test web/tests/*.test.mjs`: 61 passed, 0 failed (~230ms). Node emits its existing experimental localStorage warning.
- `go test ./...` in server: passed (29.788s latest run).
- All 7 original browser suites pass via `web/tests/run_legacy_browser.py` (37.02s total); this supplies the browser_exec helper adapter to real local Chromium and actual shipped assets.
- HTTP suites pass: bootstrap (0.92s), analysis (3.85s), episode (7.62s), five-locale HTTP (2.72s), redesign (8.65s), visual/contrast (1.59s).
- Synthetic 2,113-segment reader: initial 100 rows, zero unopened quote forms, citation to segment 2112 works, open draft survives locale/session changes without extra locale API calls.
- Light/dark snapshots at 320, 390, 768, 1440 widths, height 844: no horizontal overflow, primary visible, disabled button contrast 4.78:1 light / 4.70:1 dark, primary 44px high. Mobile light/dark screenshots visually inspected.
- Local fixture guest ready: 31.2–38.5ms; session request starts 12.9–16.8ms after navigation. These are local synthetic measurements, not production performance claims. Paint entries were not available at measurement instant.
- Final integration rerun: Go `go test -race ./...` passed (36.090s), `go vet ./...` passed; Node 61/61; all 13 browser suites passed using the existing `episode-browser-venv` interpreter. Default system Python lacks Playwright; incorrect shorthand analysis filename was corrected to `episode_analysis_browser.py`, not treated as a test failure. Bootstrap tests also block `bootstrap.js` and verify the app remains visible, localized and locked.
- Final local fixture guest-ready range 31.4–39.2ms; session start 12.8–17.0ms. These are synthetic local measurements, not live performance or paint claims.
- `git diff --check`: clean.

Evidence: `/Users/tinyserve/.hermes/cache/scratch/keinemagie-redesign/` (screenshots, measurements.json, final-suites.json). Production authenticated latency, live account integration and deployment remain intentionally unverified.
