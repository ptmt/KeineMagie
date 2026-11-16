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
- Actual Release discussion UI suite rerun on the isolated small simulator: **4 tests, zero failures**. Independent compact translator suite then completed separately: **5 tests, zero failures** (246.756s), including all five localized header/dark/accessibility loops. The earlier timed-out combined run is still not counted.
- Personally vision-inspected en/de/ru/es/fr empty keyboards, growing English keyboard, Russian XXXL dark keyboard and paired preview. Composer/Send/Done remain unobscured; French placeholder truncates within its field (not a clipped control). No new help chrome was added.
- `git diff --check` and added-line security scan pass. Original dirty worktree recorded read-only in a protected hash manifest before release; never edited.

## Backend-first release

- Reviewed source: **`2d49504dedb132dde96edc30016780cd1d0f6072`**, normal non-force push directly from the isolated candidate. Origin read back exact SHA; dirty main never checked out/reset/edited.
- [Server CI 43859065419](https://github.com/ptmt/KeineMagie/actions/runs/43859065419), build job **133270791966**, success. [Native validation 43859065377](https://github.com/ptmt/KeineMagie/actions/runs/43859065377), validate job **133270792493**, success; push upload job intentionally skipped.
- Pulled actual CI ARM64 registry artifact `ghcr.io/ptmt/diktat-server:sha-2d49504`, running image **`sha256:1f7e22e58f8913c026554257b848c34449a9c44840e9087379a3ff105b767f5f`**, OCI revision matches exact source.
- Existing original Compose base + durable `compose.translator.yml` workaround; full merged config changed only backend image. Backend-only `up -d --no-deps --pull never`; worker **`sha256:a61794a3d7e74b63d9626c453f3b0bac1b9f9f1351b0bb6349ccf564bded9382`**, worker/unrelated IDs, environment, mounts, resources, routing/security labels and network membership preserved. Private podcast network remains internal and backend/worker-only; prior proxy-network fix retained. Not a new tinyserve lifecycle or domain migration.
- Actual active-job/store/account flocks acquired nonblocking; zero active podcast jobs, one completed job, **2113 segments and translations**. Runner lifetime flock acquired only after stopping idle backend. Private backup then post-replacement hashes: **all 27 actual nonruntime durable files byte-identical**, not inferred from an earlier release count. Existing authoritative November ledger remains one acceptance entry, USD 1 reserved, reported cost 826 micro-USD, at most nine further attempts under the existing application ceiling. No provider/TTS call made.
- Dedicated TTS volume remains read-only, key UID/GID 65532 mode 0400 and readable after dropping to UID65532; host original 0600 unchanged. Source-key bytes never printed. All 54 recorded dirty-original file hashes unchanged.
- Public HTTPS health **200**, **28/28 allowlisted assets exact** against reviewed files with existing cache policy; followups/Coach/Diktat/private audio/podcasts/history guest **401**, secret/ledger/Go source paths **404**. Additional legacy `/v1/translations` unauthenticated/invalid-bearer probes return existing fail-closed **503 `TTS_AUTH_TOKEN is required`**; this shared-token compatibility route is not the authenticated personal followup route and no token/config was added to change it.
- Private backup/evidence: `/Users/tinyserve/Library/Application Support/tinyserve/services/keinemagie/deployment/release-native-followup-20261116T113949Z/`; archive SHA256 **`1c0e9e58a398b09aa5b63e9531c75faff11dd05ad4dd49dad73a79a13ad61a23`**. Binary rollback uses saved `compose.previous.yml` and prior image `4e40ce1a54d6…`; never restore historical data or remove budget holds.
- Final independent discussion xcresult: `km-followup-build/Logs/Test/Test-KeineMagie-2026.11.16_12-32-06-+0100.xcresult`; separate compact bundle `Test-KeineMagie-2026.11.16_12-36-25-+0100.xcresult`. New discussion screenshots: `/Users/tinyserve/.hermes/cache/scratch/followup-independent-shots/manifest.json` (10 captures, five locales plus keyboard/pair/applied/error/Russian XXXL dark).

Apple publication: explicit `publish=UPLOAD` dispatched **only after verified backend**: [43859886337](https://github.com/ptmt/KeineMagie/actions/runs/43859886337), exact head **`2d49504dedb132dde96edc30016780cd1d0f6072`** read back; final conclusion **success**. Validate job **133273622303**, upload job **133275273643**, both success; manual archive/export, upload and signing cleanup completed. Build **1.0 (2761.38.71)**; actual upload job log reports **`UPLOAD SUCCEEDED with no errors` at 2026-11-16T11:48:50Z**, delivery UUID `e1c36863-eeb6-48c1-afb4-052d561a6ea5`. Apple processing, tester availability and physical-device installation remain unverified. No App Store Review submission.

Final scope: 16 committed feature/doc files; additional release evidence is documentation-only. No web redesign, domain migration, other application changes or unrelated pending AnyProgress dashboard cleanup. Removed only this session's regenerated native CI `__pycache__` after verified delivery; retained screenshots, logs, result bundles, worktree and private rollback backups.

## Limitations / review gates

Independent source review completed before commit/release. No manual output editor was added (outside the user's compact-followup request). Local-only applied wording is not stored as a new immutable translation; reopen/relaunch can return to the original saved pair, while the saved thread/proposal remains available for explicit reapply. Thread is plain text, so exceptionally long server answers scroll rather than being truncated. Draft cache persistence is asynchronous while typing; accepted Send always awaits persistence. Native offline submission is deliberately unavailable until session validation restores write readiness. Simulator fixture tests establish UI/wire/lifecycle behavior, not linguistic accuracy of a real model.
