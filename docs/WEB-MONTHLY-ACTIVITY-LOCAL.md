# Web monthly activity — local candidate

> **Историческая итерация; правило ≥1000px отменено окончательным выбором пользователя 27 ноября 2026.** Теперь в Coach всегда 30px неделя, а компактный месяц — по явному действию в существующем Profile. Актуальный локальный кандидат: `WEB-PROFILE-ACTIVITY-LOCAL.md`. Скриншоты и результаты ниже сохранены как история, не как текущий дизайн.

Base: `a120d641165586eb9e5ceee0b624f7906e17da98` (includes the unpublished Podcast study/star candidate). Worktree: `/Users/tinyserve/Projects/KeineMagie-web-monthly-activity`, branch `candidate/web-monthly-activity`. Local only: no push, deployment, production account/store access, paid AI, native build or simulator changes.

## Behavior

Web Coach now shows a real calendar month: locale weekday order, numbered square days, previous/next/current month and explicit Refresh. Today has an independent outline. Day details contain the exact **recorded** count and source breakdown; incomplete history is not a mastery score. The small totals mean recorded activities and **at least** that many active days, not exhaustive lifetime totals.

Fixed count scale, identical across every month: **1–2 / 3–4 / 5–9 / 10+**. A neutral square means no retained dated events were found, **not verified zero activity**. Dashed/unfilled means unavailable evidence. Source reads that fail do not erase positive evidence from working sources, and all-source failure never becomes a grid of zeroes. The detail retains positive Podcast exercise counts even if its study-store read failed.

The grid is bounded to 350px, uses real square cells and compact controls, and stays inside mobile widths. Existing chat/composer code is unchanged. Native still requests and renders seven days; no native files were modified.

## Evidence/source audit

The previous client requested exactly one locale week and the server constructed exactly seven dates. Therefore earlier activity in the month could not appear, regardless of styling. The previous accent was translucent and capped at four; this candidate uses opaque, theme-specific count bands with tested readable day numbers rather than normalizing by the month's maximum.

The underlying sources are still `server/activity.go` and the contracts in `WEEKLY-ACTIVITY-LOCAL.md` / `PODCAST-ACTIVITY-STARS-LOCAL.md`: saved successful translations, one settled Check per Coach exercise, checked Dictation receipts, Podcast-only attribution of passage-source exercises, and immutable explicit transcript-study receipts. No request/open/star/preparation/listening event is invented. Dedup, original dates, deleted-history limits and undated evidence are unchanged. Full source stores are read; a capped history-list response is not used.

Actual Go handler output from a synthetic saved translation is retained in `monthly-activity-evidence/go-month-wire.json` and replayed unchanged through the real web assets: October 19 alone is filled, the remaining calendar is present, and today remains independent. Synthetic corrupt-store tests cover unavailable sources. Browser fixtures separately exercise transport failure, unavailable sources and retained partial evidence.

**Limit:** the supplied reference file `.../30e38820b76951d3f0098eee3b1da719f109220cbba89ae16fb9afd5b4d5516c/img_7f77fbfddcf2.jpg` was absent in this worker (direct image load and bounded cache filename search failed). No production private response was inspected. Consequently this does not claim to diagnose a specific production retrieval failure from that missing image. The verified cause of missing earlier days is the seven-day contract; unknown source coverage remains explicitly unknown.

## API and lifecycle

`GET /v1/learning/activity?start=YYYY-MM-DD&time_zone=Europe%2FBerlin&days=31`

- Optional `days` is an integer in **1…31**; omitted means **7**, preserving native and older callers. Invalid/duplicate/out-of-bound values fail with 400. Existing auth, owner header, GET-only and no-store behavior remain.
- Uses calendar `AddDate`, not elapsed 24-hour periods. Client uses local civil dates and locale weekday order, handles leap years/month lengths, and refreshes following the current month on local day/timezone changes and foreground checks. Browsed historical months remain selected.
- New server: one bounded request. An old server ignoring `days` and returning seven dates triggers at most five non-overlapping week reads, clipped to the requested month. Missing week responses stay unknown; global undated counts are not summed five times. This fallback is a bounded best-effort view, not an atomic snapshot across concurrent source edits.
- Requests are abortable and epoch/owner/month/timezone fenced. Late old successes/errors cannot replace current data. Same-scope refresh failures keep the visible saved view with an explicit failure label; 401/403 wipe it. Changed scope clears private counts before awaiting a new response. No private disk cache is introduced.
- Broken/absent response arrays and mismatched response timezone fail closed. Busy Refresh is disabled. Retry remains explicit; failed keys are retryable.

## Executed verification

- RED→GREEN: HTTP out-of-bound days initially returned 200; calendar/range/intensity tests initially failed; cached evidence survived 401 until the new regression drove its purge; invalid response validation likewise failed first.
- Full `go test ./...` passed; focused `go test -race ./... -run 'TestActivity|TestPodcast.*Activity' -count=1` and `go vet ./...` passed. Tests use actual stores/handlers, preserve Podcast dedup/source attribution, exercise 28/29/30/31-day months, both DST seasons, boundary exclusion, Berlin/New York/Kathmandu/Kiritimati and default seven-day compatibility.
- Full Node: **195 passed, 1 existing skip, 0 failed**. Month lengths, fixed scale, auth purge, invalid response, old-server merge, cancellation/late errors and saved refresh evidence covered.
- Real production web modules/CSS with local synthetic HTTP: **8 configurations**, Chromium + Playwright WebKit × 1280/390 widths × light/dark. Exercised numbered month grid, weekday headers, all count bands, today, detail/Escape, navigation, 28/29/30/31 days, injected month rollover via actual visibility lifecycle, offline retained view, retry, all-source unavailable state, old-server five-read fallback and actual Go-wire month.
- Runtime checks assert no horizontal overflow, distinct computed colors and number/background contrast >=4.5:1. Initial contrast checks caught a light band at 4.497:1; final palette corrected it. Screenshot inspection caught legend painting over the detail popup; stacking was fixed and a hit-test regression added.
- Inspected representative actual desktop/mobile light/dark captures, day detail, unknown-source and Go-wire month. PNGs, computed-color results, actual wire and test logs are in `monthly-activity-evidence/`. These are synthetic runtime evidence, not real account activity.

Reproduce:

```sh
cd server
MONTHLY_ACTIVITY_WIRE_PATH=../docs/monthly-activity-evidence/go-month-wire.json go test -run TestActivityHTTPReadOnlyContract -count=1 .
go test ./...
go test -race ./... -run 'TestActivity|TestPodcast.*Activity' -count=1
go vet ./...
cd ..
node --test web/tests/*.test.mjs
uv run --with playwright python web/tests/activity_month_browser.py
```

## Integration boundary / remaining limits

Only activity rules in `web/coach.css` were changed, not composer rules. `web/core.mjs` adds the bounded optional activity-query parameter; `web/coach.mjs` is untouched. This is intentionally independent of the parallel Enter/newline/focus composer candidate. Preserve both narrow hunks when integrating.

Playwright WebKit is not physical Safari certification. Overnight/real OS timezone changes, physical accessibility, all-locale browser acceptance and authenticated production data were not exercised. Existing lower-bound history cannot be reconstructed into a complete ledger. User preview acceptance and any publication are separate gates.
