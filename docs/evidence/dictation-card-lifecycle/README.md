# Dictation card lifecycle — local candidate

Base verified clean: `7b439023d9bf47d810c3af156695b5776589ce0e`.
Scope: web cards, additive list-only server summary, a canceled-before-admission guard, tests/evidence. No native/Xcode work, production data, provider calls, push or release.

## Authoritative mapping

The list derives optional `lifecycle_stage` from the persisted owner-scoped record **before redacting source, draft, plan and differences**. Priority is:

| Value | Label (RU / EN) | Evidence |
|---|---|---|
| `completed` | Завершён / Completed | `checked`, regardless of mistakes/score or audio availability. |
| `started` | Начат / In progress | Non-whitespace persisted draft; policy v1 `playback.whole_starts > 0` or accepted entries in `playback.listens` (including segment starts); legacy policy only: positive replay counter. |
| `ready` | Аудио готово / Audio ready | All assets required by the current preparation contract are in persisted `ready` and exist as nonempty regular files in this owner/attempt's cache. |
| `added` | Добавлен / Added | Persisted record without any higher evidence. Opening, revealing, revision, step and cursor alone are not work. |

Preparation contract mirrors the existing player: v1 whole mode requires the first whole asset; v1 passage mode requires unique assets from the current cursor through the final whole reading; legacy whole requires the first asset and legacy passage mode only its current step. Missing, unpublished, partial or failed-to-publish assets cannot produce ready. No decoding/media download, estimates, per-card API requests, new store queries or provider calls. Bounded local filesystem stat checks occur inside the existing single owner history read. Existing duration handling stays unchanged.

A new attempt starts with empty draft/ledger and unchecked state, but existing linked audio can legitimately make it **ready**. Mode changes recompute preparation requirements. Refresh/reload and deletion use existing owner/revision fences.

### Milestones, not a checklist

All four labels are ordered and passive. Only the current milestone is colored, bold and marked `aria-current="step"`. Earlier labels are neutral gray and later ones quieter gray. **There are no completion ticks or assertions that preceding stages happened.** A typed or checked attempt without audio highlights Started/Completed without claiming an audio file exists. Current stage is the highest meaningful evidence, not monotonically stored progress.

Missing or unknown future summary values from an older/mixed API do **not** become Added: omit the lifecycle unless `checked` authoritatively supplies Completed. No inferred background preparation or extra failure stages. Real preparation/error feedback remains in detail.

An accepted start is an admission, not proof of hearing or finishing audio. Canceling that accepted playback does not erase its start. A regression exposed that an **already canceled request** could previously enter the ledger; the playback transaction now rejects canceled context before admission. No UI read writes the ledger or attempt store.

## Presentation

Russian, English, German, Spanish and French. Blue/violet/amber/green active labels; 14px text, wrapping rather than tiny-font compression, semibold existing titles and unchanged whole-card button navigation. No fake interactive progress controls or extra tab stops. Existing cards are buttons, not URL links; this patch preserves that established interaction rather than inventing a new route contract. Scoped dark card colors now match the surrounding dark shell.

## Executed verification

- RED: Go HTTP/store lifecycle matrix returned missing stage; mounted Node lifecycle tests lacked track/current step; real Chromium failed active weight/color assertions; canceled-start HTTP test admitted a start (200 instead of failure).
- Full `go test ./...`: PASS (`go-all.log`).
- Relevant `go test -race ./... -run 'TestDictation(Library|Playback|Lifecycle|Attempt|Delete)' -count=1`: PASS (`go-race.log`).
- `go vet ./...`: PASS (empty `go-vet.log`, exit 0).
- Full Node suite: **166 passed, 0 failed, 1 existing opt-in Go-wire test skipped** (`node-all.log`). Node also emits its existing experimental localStorage warning.
- Real Go HTTP/store fixtures: all four stages; wrong checked answer/no audio; whitespace; reveal/open; missing/unpublished/partial assets; all passages including final whole; legacy current asset/replay; v1 legacy counter ignored; root whole counter and segment ledger; denied/missing/canceled-before-admission start; cancel-after-admission; new attempt/cache reuse; remote mode edits; persistence across handler recreation; owner isolation; deletion; byte-for-byte no writes on list.
- Actual full app + Go DTO in Chromium: **30 cases**, 4 cards × five locales × light/dark × 320/390/1280 widths (`browser-result.json`). Readable wrap/no overflow, all labels localized, one current step, four distinct active colors, weight >=600, 14px labels, no nested controls, adjacent-card keyboard focus. Minimum settled contrast **5.28:1 light / 6.58:1 dark**. Reduced motion avoids sampling transient theme interpolation.
- Same real app fixture also verifies new-attempt Ready → remote mode edit Added → typed Started → checked Completed → deletion on library refresh. Explicit setup/mutations use the isolated fixture's authenticated API; **library rendering makes zero media requests and zero mutation requests**, and leaves persisted store bytes unchanged during the presentation matrix. No provider calls.
- Existing library Chromium regression: **45 cases**, 0/1/3 cards, five locales, three widths; keyboard creation/navigation/menu, cancellation/confirmed deletion, stored draft recovery, stale remote deletion, owner clearing (`regression/result.json`, `library-regression.log`).

## Inspected actual-app previews

Synthetic records and a real synthetic silent WAV; not user data or generated speech.

- `app-ru-light-1280.png`: full desktop grid, all four stages.
- `app-ru-light-390.png`: full mobile list, all four stages.
- `app-ru-dark-1280.png`: dark desktop grid.
- `app-ru-dark-320.png`: narrow dark cards wrapping without clipping.

These were visually inspected, not merely captured. Other 320/390 captures are included. Header navigation's narrow 320px text wrapping predates this card-scoped change.

## Safe reproduction

Start `TestDictationLocalFixture` from `server` with a fresh scratch `DICTATION_FIXTURE_DIR`, an unused `DICTATION_FIXTURE_PORT`, and matching `WEB_ORIGIN`. With Playwright/Chromium installed, pass the same fixture directory to `web/tests/dictation_library_lifecycle_browser.py`. This test writes only the disposable fixture's ready WAV and history, then exercises actual authenticated endpoints. Never use a production store.

For the existing module regression, start a local static server rooted in `web`; set `DICTATION_LIBRARY_BASE` to its `tests/dictation-focused-fixture.html` URL and `DICTATION_LIBRARY_OUT` to a separate evidence directory before running `web/tests/dictation_library_browser.py`.

Candidate only; visual approval and any release remain with the parent/user.
