# Web activity: week in Coach, month in Profile — shipped

**Current delivery:** deployed in `c3334db432e18ee81c50723fe2e0d312494124bb`; see [coherent release receipt](COHERENT-OPTIONS-RELEASE.md). The local-only/preview statements below describe the earlier candidate checkpoint, not current production.

## Current contract (27 November 2026)

The final user choice — «А лучше оставить недельный стилизованный блок, а месяц в профайл куда нибудь перенести» — **supersedes the ≥1000px inline-month rule**. Earlier monthly/responsive documents and PNGs are historical evidence, not the current requested design.

- Coach: seven styled 30px squares at every width; count intensity, independent today outline, exact day/source details. No month, sidebar, totals or permanent coverage footnote above chat.
- Existing **Profile → Learning profile → Activity** disclosure: explicit, lazy read-only month. Maximum width 300px, approximately 39px cells; previous/next/current month and Refresh retained. Totals remain lower bounds; partial/unknown coverage, undated records and source explanations remain available.
- Disclosure toggles and resizing do not repeat the same month read. Account close/logout clears and fences the month; reopening explicitly reads current retained data. Week and month have separate owner/range/timezone-scoped states using the unchanged reader and API.
- A delayed profile-settings response no longer steals focus after the user has entered the calendar (reproduced RED, corrected GREEN).
- No backend, completion policy, historical data, native UI/fonts, starred-source selection or composer implementation changes. No new top navigation or route.

## Source and boundary

Fresh isolated worktree `/Users/tinyserve/Projects/KeineMagie-profile-activity`, branch `web/profile-activity-week`, fetched `origin/main` **29ba00a7a2e71507e397c32a892011d578117e3d**. Original dirty `/Users/tinyserve/Projects/KeineMagie` was not edited. Supplied screenshot was inspected: inline month occupied most of the area before the exercise.

This is **local only; not pushed or deployed**. Last supplied/repository-recorded web release remains `046099dfa71f8b1880b2fd8b3575ab47c7246efe`; native source remains `22791e6fb872e18cbe084883d3d73a920623b5d9`. Production was not mutated or authenticated. Browser APIs are isolated synthetic loopback fixtures; no paid provider requests.

## Executed verification

- Node: **197 passed, 0 failed, 1 existing opt-in Go-wire skip** (198 tests).
- `activity_profile_browser.py`: Chromium + Playwright WebKit, **16** combinations of 390/999/1000/1280px × light/dark, plus **2** delayed-profile focus cases. Actual Profile/disclosure/month/week navigation, count details, focus, draft, logout, bounded cells and no navigation-triggered AI requests.
- `activity_lifecycle_browser.py`: **2** browser cases, promises deliberately ignoring abort; stale range/owner/close/destroy success and error, no resize reads, five-locale month scope reuse.
- `activity_month_browser.py`: **8** desktop/mobile/theme combinations; 28/29/30/31 days, rollover, offline/retry retention, unavailable versus zero, old weekly-server fallback, retained Go-wire replay, count-label contrast ≥4.5:1.
- Composer keyboard: **4 Chromium + 4 WebKit** variants; Enter/Cmd/Shift, IME/repeat/modifiers, draft/selection, menu, pending/Stop and geometry.
- Composer optical alignment: **4 Chromium + 4 WebKit** variants; placeholder/emoji/multiline, growth/shrink/cap, menu caret, 44px controls and Stop.
- Existing Coach parity browser: **4** Chromium variants, actual answer/assessment/pending/history/activity/logout flow.
- `go test -race . -run 'Activity' -count=1`: passed; unchanged backend semantics.

Node mock DOM gained `closest()` for the new visibility predicate. A clean archive of `origin/main` (web plus server static-contract files) also produced 197 passes / one opt-in skip. Early image review caught the neutral day losing its square style under the generic Coach button rule; a failing computed-style regression now protects it. An occasional fixture socket closed during page/logout teardown (BrokenPipe). Three intermediate multi-case runs timed out before the initial app mount (one captured WebKit case had no page errors); no production fix is claimed for that intermittent harness/bootstrap issue. Failed receipts are retained separately. The two subsequent complete placement/lifecycle runs and final month regression passed (`network-diagnostic.log`, `network-diagnostic-2.log`, `final-month.log`). Playwright WebKit is not a physical Safari/device test. No live owner data, native build or real-model quality claim.

## Inspected preview

Runtime PNGs were captured and inspected before the final regression suite:

- `profile-activity-evidence/chromium-1280-light-week.png`
- `profile-activity-evidence/webkit-390-light-week.png`
- `profile-activity-evidence/chromium-1280-dark-profile.png`
- `profile-activity-evidence/webkit-390-dark-profile.png`

Machine receipts and additional themes/states are in `profile-activity-evidence/`. Re-run with `uv run --with playwright python web/tests/activity_responsive_browser.py` (compatibility entry point for the new Profile placement plus lifecycle), `activity_month_browser.py`, and `node --test web/tests/*.test.mjs`.

Next: user preview/approval, then separately authorized publication. No deployment performed.
