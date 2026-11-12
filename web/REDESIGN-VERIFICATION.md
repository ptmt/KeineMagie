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

Evidence: `/Users/tinyserve/.hermes/cache/scratch/keinemagie-redesign/` (synthetic screenshots/measurements). Exact-commit backend deployment, live public guest checks, independent Astra follow-up and verified iOS upload are recorded in `docs/NEUTRAL-DESIGN-RELEASE.md`. Production authenticated latency/live account integration remain unverified.

## Podcast screenshot and immediate history translation follow-up

- Feed name is the section's single heading. Feed-level refresh/unsubscribe live in a localized native disclosure; the unrelated global refresh is hidden on feed routes and named Refresh list elsewhere. Direction and a short explicit processing explanation remain above episodes.
- Dense neutral episode rows combine date/status metadata. Prepared episode titles are underlined real navigation links, replacing redundant Open/Details buttons; cancel/retry remain explicit. Delete is only inside an episode disclosure, retains confirmation and existing owner/CSRF contracts. All disclosure/add/prepare targets are at least 44px high; add and disclosure targets are also 44px wide. Native Enter disclosure interaction, Escape/focus return, outside click and locale-preserved open state are exercised.
- History now renders the exact complete saved translation immediately below the muted source, with language attributes, preserved line breaks, escaping through textContent and no truncation or expansion requirement. Existing reopen/copy and owner-isolation behavior remain unchanged.
- `podcast_design_fixture.py` serves actual assets plus explicitly synthetic same-owner API data: 50 feed episodes, one ready job, nested transcript and history. It has no preparation/inference implementation and uses no production credentials. New `podcast_design_browser.py` and `history_preview_browser.py` cover actual rendered behavior, confirmed destructive fixture mutations/readbacks, six job states, four widths, light/dark, literal markup safety and exact full output. Two old history tests now assert source and translation separately rather than treating the sole strong element as source.
- Final verification: Node 61/61; seven legacy browser suites; bootstrap, episode analysis, episode, five-locale HTTP, redesign, visual/contrast, copy, plus both new suites all passed with `/Users/tinyserve/.hermes/cache/scratch/web-podcast-review-venv/bin/python`. No page errors in new suites. `git diff --check` passed. Existing Node experimental localStorage warning remains.
- Actual independent review used `run_review.py`, `nous`, exact `openai/gpt-6-astra`, `max`, fallback disabled, twice. Catalog and transport audit confirm requested model/effort and returned Astra labels, not independent upstream attestation. Initial review saw only hidden-tab skeletons; bringing the harness tab forward enabled visibility-gated reads. The independent after-review inspected populated desktop 1280×847 and mobile 390×844 via screenshots/auxiliary vision and found no material issues in changed controls/history. Minor residual feedback: mobile pre-list header can be tighter, and existing unavailable-nav subtitles are small. Neither is a claimed production failure.
- Screenshots visually inspected: `/Users/tinyserve/.hermes/cache/scratch/podcast-design-evidence/feed-{light,dark}-{390,1280}.png`. No native files, production data or provider quota were changed during implementation/review.
- Independent release review found no blocking security or logic issue: saved text uses textContent (not HTML/entity conversion), disclosure controls retain native semantics/confirmation, unchanged mutation transport keeps CSRF and owner guards, keyed reconciliation keeps pending/menu state and opening/refreshing does not start AI. Added a 1,200-line Unicode/literal-entity/leading-and-trailing-whitespace history regression and verified exact textContent on immediate display, locale change and reopen.
- Release integration reran Node 61/61, podcast design/history/five-locale HTTP browsers (all passed, no page errors), Go tests and vet (passed). Existing 16-suite browser pass is the implementation gate above; release status/provenance is recorded in `docs/WEB-PODCAST-DESIGN-RELEASE.md`.
