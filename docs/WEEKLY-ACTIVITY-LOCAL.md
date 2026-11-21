# Weekly activity — isolated local candidate

Base: `39ed59d` (`origin/main` when work began). Branch `candidate/weekly-activity`; worktree `/Users/tinyserve/Projects/KeineMagie-weekly-activity`. No deployment, Apple upload, production account/data access or paid provider calls. Original dirty worktree was not edited.

## What the number means (important)

This is **retained completed Check workflows**, not mastery, listening time, translated requests, or an exhaustive all-time exercise ledger. It is a lower bound. A dot on a square means coverage is incomplete; tapping it explains the exact date/count and missing coverage. VoiceOver says “at least N” or “No completion data. Not a verified zero.”

Source inspection before implementation:

| Section | Actual persisted evidence | Candidate interpretation |
|---|---|---|
| Coach | `coach.go`: owner-scoped turns, attempt `At`, outcome/state and prior attempts; `coach_assessment.go`: immutable original answer time retained on recheck | One settled explicit Check per exercise turn. Correct/wrong/ambiguous all count; skipped, pending/failed/canceled assessments, generated turns and discussion do not. A completed prior assessment survives a later failed recheck. Same exercise never counts twice. Observation exclusion/reset is not erasure of activity. |
| Dictation | `dictation_assessment.go`: checked flag plus immutable receipt `At`; `dictation_library.go` already maps checked to lifecycle `completed`; `dictation_progress.go` explicitly distinguishes partial and legacy-unknown | One checked workflow per retained attempt ID, at its receipt date. This **includes a partial dictation check**, because it completes the existing Check workflow. It does not assert the entire text was finished. Optional hybrid AI failure does not undo the saved deterministic Check. |
| Translator | `translations.go` records a translation request/result/creation, not learner exercise completion | `unsupported`, excluded. No translation request relabeled as a completed exercise. |
| Podcasts | `podcast_store.go` / worker completed state means preparation/transcription/translation; vocabulary status history is self-report | `unsupported`, excluded. No views, listens, playback starts, preparation jobs or AI requests counted. |

Historical time caveats:
- Coach attribution uses the persisted original **learner Check timestamp**, not an invented provider-finish timestamp. A delayed recheck remains on the original Check date.
- Historical checked Dictation records without a receipt timestamp are **undated**, never assigned their item creation date. New checks already persist a receipt timestamp through the current check handler (including old clients without `hybrid`). No parallel ledger/migration was necessary for this retained-evidence contract.
- Deleted records cannot be reconstructed; no retention ledger coverage watermark exists. Consequently **every current API day is `partial`**, even when `known_count` is zero. Client supports a future `complete` day and verified zero, but this server does not manufacture one.
- If the product instead means only full-text Dictation completion, that is a different metric: require `alignment.complete` (explicit learner declaration), and do not silently reinterpret the existing completed workflow. If it requires lifetime totals surviving deletion or counts from Translator/Podcasts, define new explicit completion actions + an append-only ledger separately. This candidate does not claim that broader coverage.

## Additive contract / privacy

`GET /v1/learning/activity?start=YYYY-MM-DD&time_zone=Europe%2FBerlin`

Optional `X-Activity-Owner` must match the authenticated opaque owner. Uses existing learning authentication/browser rules; `Cache-Control: no-store`; other methods rejected. Start is the client's locale-week start. Timezone must be valid and explicit; no server-local fallback. Seven dates advance via calendar arithmetic (`AddDate`), not 86400-second intervals.

```json
{"version":1,"time_zone":"Europe/Berlin","days":[{"date":"2026-11-16","known_count":0,"coverage":"partial"}],"sources":{"coach":"retained","dictation":"retained","translator":"unsupported","podcasts":"unsupported"},"undated":1}
```

Example abbreviated to one day; real replies always contain seven. `undated` counts retained checked workflows which cannot be assigned a day, not additional counts for this week. Source `unavailable` means its storage read failed; other successful sources still contribute their lower bound. No IDs, answers, prompts, source text or model requests are returned. GET reads owner stores under their existing locks without mutating JSON. Existing endpoints and storage schemas are unchanged.

## Native behavior

Pinned at the top of Coach's scroll surface; **30pt total header, seven 30×30pt squares**, weekday hints inside, no additional title. One neutral adaptive grayscale, intensity capped for contrast. Today is an independent outline, including an unknown/empty day. Previous/next week controls plus Current week in the context menu; current locale week by default, no future-week navigation. Explicit day details/localized AX strings in DE/EN/RU/ES/FR use the separate `Activity.xcstrings` table.

Refresh: Coach checks, returning to the selected tab, foreground, local calendar-day or timezone change. Minute-aligned Timeline ticks do not fetch unless the day/key changes. Snapshot keys include session generation, origin, owner, zone and week. An obsolete/canceled request cannot relabel the next week/owner; same-generation 401 still revokes identity. Offline, old server (404), invalid response or failure means unknown, **not cached complete counts**; there is intentionally no private activity disk cache or automatic mutation/inference.

The 30pt constraint intentionally bounds only strip typography. At maximum Dynamic Type, full date and count remain in AX and tap detail. Existing chat/composer typography remains unchanged. Buttons have the requested 30pt visual/AX geometry, not a claimed 44pt target.

## Executed verification

- TDD RED: Go adapter absent; activity HTTP returned 404; Swift models/API absent; actual Release UI found no activity strip. GREEN implemented corresponding slices.
- `go test -race ./...` passed (101.672s); `go vet ./...` passed. Targeted activity tests cover real authenticated handler, 401/403, invalid dates/zones, unsupported modules, zero provider dispatch, local-day conversion, DST zones/fractional and distant zones, prior-check deduplication, observation reset, read-only restart/readback and corrupt source storage.
- Actual Go-handler JSON saved to scratch and decoded by production Swift DTO in `ActivityTests.actualGoWireWhenProvided` with `ACTIVITY_WIRE_PATH` set.
- Full Core: 108 XCTest, 5 expected skips, 0 failures; 88 Swift Testing passed (includes 4 activity tests). `native/ci/test_connection_lifecycle.py`: 124 actual-AppModel synthetic transport tests passed, including held old-owner activity read, replacement, 401 and no further offline network requests.
- Release UI on existing normal simulator `93E1113F-6736-4CCB-827D-0E2F1C3876EA`: **2 light + 2 dark tests passed**, xcresult summaries parsed. Asserted 30pt header, seven 30pt squares, week navigation, unchanged rectangle after a real synthetic Check response updates the count, full-width containment and Russian AXXXL unknown-not-zero labels.
- RED AXXXL revealed a 45pt AX union from automatically scaled chevrons even with 30pt cells. Explicit decorative font size fixed it; final suites above pass.
- A first green UI run was terminated during app startup and executed no successful tests; retained `activity-green.xcresult`. Retry and final light/dark runs actually executed and passed. It is not counted as acceptance.
- Inspected actual XCTest PNGs in `docs/activity-evidence/`: normal light/dark populated synthetic checks and Russian AXXXL unknown state. No photoshopped UI or production evidence. Russian capture shows the existing large chat scrolled within its viewport; the strip itself remains contained.

Reproduce Go→Swift bridge:

```sh
cd server
ACTIVITY_WIRE_PATH=/Users/tinyserve/.hermes/cache/scratch/activity-wire.json go test -run '^TestActivity' .
cd ../native/Core
ACTIVITY_WIRE_PATH=/Users/tinyserve/.hermes/cache/scratch/activity-wire.json swift test --filter ActivityTests
```

Local retained results: `/Users/tinyserve/.hermes/cache/scratch/activity-final-light2.xcresult`, `activity-final-dark.xcresult`, `activity-go-all.log`, `activity-swift-all.log`, `activity-model.log`. Durable screenshot/summary copies are committed here.

## Integration / remaining gates

Not published and not declared release-ready. SE was initially deferred because `56A70197-59DE-4410-9E76-25272244E9C8` was booted outside this task. After it was released and both devices had no running test/app processes, it was borrowed serially: **2 light + 2 dark Release UI tests passed**, including Russian AXXXL; xcresult counts parsed and all four exported PNGs inspected. Same 30pt geometry/count-refresh assertions passed. `activity-final-se.xcresult` and `activity-final-se-dark.xcresult` are retained in scratch; durable SE light/dark/AXXXL copies are in the evidence directory. No new simulator/clone was created. Native overnight/OS-timezone-notification lifecycle, spoken VoiceOver, all-locale native dialogs, physical device and independent review remain unverified. Calendar arithmetic is tested; that is not an overnight timer claim. Web UI is unchanged; backend contract is available for a later web strip.

Avoid collisions with the parallel Coach bubble/context-vocabulary candidate:
- `native/App/CoachView.swift`: **one** `.safeAreaInset(edge: .top, spacing: 0)` before `.scrollDismissesKeyboard`; preserve the other candidate's message/composer redesign.
- `native/App/AppModel.swift`: new independent `loadActivity(start:timeZone:)` before `scopeCoach`; no existing methods modified.
- `native/App/SimulatorSessionFixture.swift`: one synthetic `/v1/learning/activity` GET branch, gated by `KM_SIMULATOR_ACTIVITY_FIXTURE=1`.
- `native/Core/Sources/KeineMagieCore/Podcasts.swift`: independent GET method before `coach`.
- `native/ci/test_connection_lifecycle.py`: one ActivityTests source-copy line.
- `server/learning.go`: new authenticated route before Coach; no existing mutation behavior changed.
- All other additions are named Activity/activity and this document/evidence. No `Localizable.xcstrings`, Coach DTO, assessment/source rules or web file edits.
