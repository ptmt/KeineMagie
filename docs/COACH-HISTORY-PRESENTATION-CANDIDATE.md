# Coach history/status/scroll — independently reviewed local candidate

Integrated locally onto origin/main `4613d315eb1f2d5b12d8184546e5353be2b04454`, including podcast release `1bdffc820c668beb69395bb604f233cfd5af9f35`. Branch `candidate/coach-history-status`, isolated worktree `/Users/tinyserve/Projects/KeineMagie-coach-history`. No push/deploy/upload. Original dirty checkout and AnyProgress untouched.

## Semantics and review fixes

- Presentation only: complete turn groups recent when latest valid turn `at`, attempt `at` or `reviewed_at` >= opening time minus 86,400 seconds. Boundary included, DST/offset independent; window resets on entry. Unknown/invalid/future timestamps remain visible; no backend rewrite/deletion.
- Earlier defaults hidden, no old-active exception. Earlier cycles backward through replacement pages of **at most 50 older groups**, alongside all recent groups; oldest page's next Earlier collapses. Web also offers Latest beside Earlier. A composer-adjacent Awaiting answer link opens a hidden last unanswered exercise's page, so contextual actions do not refer to an unreachable task. Local paging only, no API/store refactor.
- Completed correct/wrong/uncertain attempts share neutral gray surfaces. Unanswered/skipped and awaiting exercises use calm red plus readable text; checking is neutral, not failed. Existing answer spoiler/reveal semantics retained.
- **Corrected regression:** only Source disclosure/citation navigation removed. Contextual **Hint remains** on both clients, uses existing exact `reveal` / `source` action, preserves composer draft and displays authorized revealed quote/explanation inline. No new AI source querying/evidence claim. Source IDs never displayed.
- Entry/load and own-send follow actual bottom; manual earlier reading/draft edits do not intentionally follow arrivals. Latest offered away from bottom. Existing owner and viewport receipt fences retained; no blanket mark-read/reset or additional provider call on opening.
- Native retains eager VStack for exact geometry, but only one older page. Value ISO8601FormatStyle parsing replaces per-row formatter construction.

## Measured contrast and UI inspection

Explicit opaque native secondary/placeholder colors and surfaces avoid material-opacity ambiguity. Mathematical WCAG contrast across specified surfaces: dark minimum **8.91:1**, light **6.88:1**. This is a palette calculation, not a claim about all native controls, screenshot antialiasing or VoiceOver.

Chromium computed-style foreground/background alpha composition on task label, prompt, learner answer, answer placeholder and composer placeholder, all five locales: dark minimum **8.96:1**, light **7.11:1**. Disabled controls excluded. Red is supplementary surface/border, not the sole status indicator.

Actual Release screenshots inspected: readable status/placeholders, latest answer field and composer visible, gray completed cards and muted-red awaiting. Partial old content above viewport is normal scroll. XXXL Russian placeholder still truncates (existing field behavior); full localized accessibility name retained. No observed page-wide horizontal overflow. English checking screenshot neutral. Five-locale largest-type screenshots cover awaiting/history, not five-locale checking.

## Combined verification after integration

- Node: **113 passed**, zero failures (`node --test web/tests/*.test.mjs`).
- Native Core: **56 XCTest executed, 1 existing Go-wire fixture skipped**, zero failures; **72 Swift Testing passed**.
- Real AppModel harness `native/ci/test_connection_lifecycle.py`: **93 Swift tests passed**, Python wrapper passed.
- Full `go test -race ./...` and `go vet ./...`: passed. Integrated podcast exact-owner auth fixture retained, no duplicate auth fix.
- `test_coach_compact.py`: 2 passed; `test_coach_contrast.py`: 1 passed.
- Production DOM synthetic-loopback Coach browser: dark/light five locales, Hint exact action/target and draft, Earlier/reload, gray outcomes, Source absence, initial/own-send bottom, reading/draft retention, viewport resize and delayed row layout passed. Existing Coach chat/actions browsers passed.
- Podcast overview browser: **39 checks passed** using its required browser_exec helpers (direct Python invocation cannot provide `cdp`). Latest three/feed, author, coverage, locales/narrow layouts, focus, Back/reload, no generation, logout/stale response all verified. `web/app.mjs`, `web/i18n.mjs`, `web/styles.css`, auth test unchanged versus integrated main.
- Release iPhone 17 Pro simulator `C7D5A3D2-CD63-46FC-B7A4-A8AB6CE82AEF`: **6 UI tests passed, 0 skipped/failures**, read from xcresult. Includes five locales XXXL dark, initial/send/Earlier, draft/progress, Hint without Source, checking/correction and 200/1000 archives.
- RED/GREEN: Hint browser failed before fix (`Contextual Hint must remain`); bounded-window JS export/Swift members absent before implementation. New window tests pass and assert original snapshot/order preserved.
- `git diff --check`: clean.

## Performance (synthetic, local samples)

Native Core classification/window selection, three iterations: before parser optimization 200 groups 188ms / 1000 groups 926ms; after **1.11ms / 5.22ms** (macOS Debug). Not statistically controlled.

Native Release UI 200/1000 archives: launch + tab + XCTest query **9.44s / 8.27s**; Earlier tap + AX queries **2.13s / 2.10s**. Includes XCTest synchronization, **not frame times**. Nearest 50 old rows available, oldest absent, initial recent bottom reachable. No Instruments memory/FPS claim.

Chromium 200/1000: initial navigation **48ms / 126ms**; old-active reveal **87ms / 140ms**, 51 rendered groups (50 old + one recent). Second Earlier remains 51, not accumulating pages. Timing varies with concurrent tests. Large recent-only history remains eager and an explicit scaling limit.

## Evidence / remaining gates

- Final Release: `/Users/tinyserve/.hermes/cache/scratch/coach-review-ui3.xcresult`
- Export manifest: `/Users/tinyserve/.hermes/cache/scratch/coach-review-final-evidence/manifest.json`
- Normal dark: `2465B159-613C-43E8-84ED-998E9169022E.png`
- XXXL Russian: `612EE060-D25F-44A6-8566-D6E03A089284.png`; prior identical layout `A976916A-8DC5-4ED4-8D13-2729E1F2305D.png` visually inspected.
- Checking: `833AE724-26B3-4D1B-A4EB-2E41DF642DC2.png`; prior same state `854682C2-B051-4C2F-8198-5D434014469F.png` inspected.
- Native benchmark attachments: `51F904F3-D313-4291-B821-1CAB6B483296.txt` (1000), `99B5A250-33F0-4AD4-9AC7-E563189B1643.txt` (200).
- Web captures/computed contrast JSON: `/var/folders/t0/l_p2xys924lbstg8jzlq61vr0000gn/T/coach-history-evidence/` (inherited Playwright TMPDIR). Execution logs: configured scratch `coach-review-*-final.log`, `coach-review-go-race.log`, `coach-review-go-vet.log`.

Synthetic only; no private data, real provider/TTS/auth or pedagogical accuracy claim. Physical Safari keyboard, hardware keyboard, VoiceOver spoken traversal, complete legacy native suite and on-device Instruments unverified. Latest activity uses available persisted timestamps, no manufactured completion timestamp. Parent review/authorization required before push/deploy.
