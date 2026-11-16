# Native translation discussion candidate

## Scope and baseline

Local, uncommitted candidate in `/Users/tinyserve/Projects/KeineMagie-native-followup`, branch `candidate/native-translation-followup`. Based on verified origin/main `879552de52d57d3cc5e26362f533775a8b3155a1`, containing native compact translator `cb9811e5334b2fbf8ad7c23b75c9ab15a69a1bc3`. The dirty main checkout and Diktat work were not edited. No push, deployment or Apple upload.

The existing web implementation was read (`web/translator-followup.mjs`), together with the actual server implementation and pairing/limit tests. This adds native parity for voluntary clarification, not automatic explanation or a separate inference service.

## User flow

- One quiet action below the result, collapsed by default, with a 44-point target. History exposes the same action beside Copy rather than a new panel.
- A native discussion sheet focuses the bounded 1–5-line composer above the keyboard. No persistent explanation cards, onboarding prose or counters except near the question limit.
- Opening, restoring and typing perform no inference. Only Send posts the exact accepted source/result snapshot and saved record ID.
- Answers are ordinary selectable plain text. Suggestions remain behind a disclosure; expanding it dismisses the composer keyboard intentionally to make the source/result preview readable on a small iPhone.
- A changed source shows both source and translation before **Use both**. Translation-only legacy turns use their captured `current_source`, falling back to the saved original only when that field is absent. Applying is atomic, local-only, and does not alter original history. The result Copy button uses the current applied result.
- Closing cancels the local operation and ignores late transport; its persisted request remains available for an explicit exact-ID retry. No automatic retry/AI call occurs on reopen or relaunch.

## Existing API reuse and safety

`POST /v1/translation-followups`, bearer auth for native (no browser CSRF). Native sends `history_id`, `request_id`, `question`, `locale`, `expected_turns`, and paired `current_source`/`current_translation`; deterministic sorted JSON preserves the exact retry body across process recreation. Existing selected personal model, strict answer/optional proposal schema, owner history, shared 100/day plan, six questions per thread, 2,000 Unicode scalars per question, 8,000 scalars per draft text and 90-second timeout remain authoritative. No fallback model or provider/TTS calls were made during verification.

The only server production change adds the same optional `X-Translation-Owner` pre-work fence already used for native translations. Native still requires existing authenticated write readiness for followup submission; advisory provider catalog status is not consulted. Offline trusted same-owner cached history/discussion is readable but cannot submit or apply. Generation, owner, record existence and cancellation fence completion. Delete, logout and 401 clear discussion selection; logout invalidates queued writes and removes the new cache dataset as well as history. Accepted request snapshots are written before transport, in the existing protected origin/owner cache. Thread data is durably saved on the server and included in normal history/cache decoding; loading it never generates an answer.

## Executed verification

All data and sessions below are synthetic fixtures, not private user history.

- TDD RED: missing Swift followup DTO/client/model members; actual native missing action; Go expected-owner request returned 404 instead of 403; logout cache recreation exposed a retained draft. Each corrected and rerun green.
- Full Go suite `go test ./...` passed (`diktat/server`, 68.494s); `go vet ./...` passed. Existing conversation, limits, directions, cancellation and pairing server tests remain unchanged.
- Actual production Go types serialized by `TestNativeFollowupWireFixture`; Swift decoded that generated JSON, including omitted/nil threads, null revised source, legacy captured source and paired proposals. Full Core suite: **72 tests passed** with `KM_NATIVE_FOLLOWUP_WIRE` set.
- Actual AppModel harness: **90 tests passed**. New followup tests exercise explicit-send-only, coalescing, immutable baseline, explicit paired apply, persisted byte-identical retry after model/cache recreation, edits during a suspended request, cancelled late completion, 429, 401, delete, logout, cache purge and different-owner generation fencing. Auxiliary provider status deliberately fails without blocking Send. Readonly preserves readable context and emits no POST.
- Native localization suites: **9 tests passed**; all new app keys have en/de/ru/es/fr translations.
- Release simulator UI suite: **4 tests, zero failures**, small 375×812-point iPhone simulator `0C5514DC-1F55-4D9C-836E-A0114903477A`, parallel simulator cloning disabled. Exercises real translation fixture → compact action → focused keyboard → growing composer → Send → explanation → disclosure → both-source preview → Use both → current source/result; empty Send disabled; retained-question error/retry and one accepted turn; all five localized empty composer screens; Russian accessibility XXXL dark keyboard Send reachable.
- Existing compact translator Release tests: all **5 individual tests passed** (direction/keyboard preservation, inline Copy, geometry, five-locales/dark/accessibility header, other-tab toolbars). Combined run exceeded its 300-second shell budget after those five and the first followup test; therefore it is not reported as a completed combined suite. Followup suite was rerun separately to full success.
- `git diff --check` passed. No signing/release settings changed.

Final Release result bundle:
`/Users/tinyserve/.hermes/cache/scratch/km-followup-build/Logs/Test/Test-KeineMagie-2026.11.16_12-25-30-+0100.xcresult`

Exported screenshots in `/Users/tinyserve/.hermes/cache/scratch/followup-verified-shots`:
- `C72F0C7A-C8D8-4481-9A0B-44F32FBC95B5.png`: small iPhone keyboard, growing composer.
- `924E7ADF-385F-4033-86EE-BD7CBA32AFE0.png`: paired source/translation preview.
- `44238B8A-5A05-4E5F-8E55-57ACECD21197.png`: applied pair, immutable history retained.
- `DCB052D5-C080-4975-B89F-EB392BF4A852.png`: retryable error and retained draft.
- `E185388F-E9D5-421C-9B3D-699572C092B6.png`: Russian dark accessibility keyboard.
- `manifest.json`: all five localized keyboard captures and attachment mapping.

Earlier equivalent successful screenshots were personally inspected with vision: keyboard and Send unobstructed, paired proposal visible and explicit Use both. No live provider quality, physical-device keyboard/VoiceOver spoken order or TestFlight delivery claim is made.

## Independent review — 16 November 2026

Reviewed the actual diff against `879552de52d57d3cc5e26362f533775a8b3155a1`, including web parity, server owner/CSRF boundaries, native cache leases, pre-POST persistence, retry bodies, generation/cancel/delete/401 fences and paired local apply. No blocking production defect found; no redesign or manual editor added. Blank sheet space is intentional room for the thread. The existing compact header, direction menu, inline Copy, immediate feedback/shimmer, Coach and Diktat sources are retained.

Additional synthetic regressions prove optional-owner legacy web replay (no new header required), matching/mismatching expected owner, missing/wrong CSRF, cross-origin and cross-owner history denial with zero provider calls/quota. Actual AppModel additions prove exact whitespace/Unicode/current-draft snapshot, stale explicit paired apply, nullable revised-source fallback to the captured source, storage failure before transport and retained exact-ID retries for 403/404/409/502/503.

Independent execution:
- Full Go race: `go test -race ./...`, pass (80.101s); targeted followup/strict-schema/ownership/browser race tests pass; `go vet ./...` pass.
- Full native CI discovery: 53 Python tests, one existing skip, pass; actual AppModel harness **93 Swift Testing tests** pass.
- Actual Go→Swift followup wire: full Core **52 XCTest cases (one existing separate podcast-wire skip) + 72 Swift Testing cases**, pass. Native discovery separately executes actual podcast/Coach wire contracts.
- Actual Release discussion UI suite rerun on the isolated small simulator: **4 tests, zero failures**. Existing compact suite had 5 individually passing tests; no claim that its timed-out combined run passed.
- Personally vision-inspected en/de/ru/es/fr empty keyboards, growing English keyboard, Russian XXXL dark keyboard and paired preview. Composer/Send/Done remain unobscured; French placeholder truncates within its field (not a clipped control). No new help chrome was added.
- `git diff --check` and added-line security scan pass. Original dirty worktree recorded read-only in a protected hash manifest before release; never edited.

Release evidence will be recorded below only after real CI/deployment/Apple output.

## Limitations / review gates

Independent source review completed before commit/release. No manual output editor was added (outside the user's compact-followup request). Local-only applied wording is not stored as a new immutable translation; reopen/relaunch can return to the original saved pair, while the saved thread/proposal remains available for explicit reapply. Thread is plain text, so exceptionally long server answers scroll rather than being truncated. Draft cache persistence is asynchronous while typing; accepted Send always awaits persistence. Native offline submission is deliberately unavailable until session validation restores write readiness. Simulator fixture tests establish UI/wire/lifecycle behavior, not linguistic accuracy of a real model.
