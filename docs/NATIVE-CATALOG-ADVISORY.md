# Native catalog advisory — reviewed release

## Independent release review

Independent source/security review found no blocking regression: provider application HTTP 401 invalidates the session and clears private in-memory state, while a successful connected/catalog-unavailable response remains advisory. Existing generation/refresh/connection fences prevent stale responses crossing identity boundaries. No credential replay, paid inference, backend change or deployment is part of this release.

Fresh reviewer execution passed 48 native Python checks (one existing skip; includes 42 actual AppModel tests), 68 Core tests, four targeted Go race tests (catalog 401/403/500, native/browser owner contract, idempotency and receipt admission), and all five ad-hoc signed Release simulator catalog/outbox UI tests. Actual xcresult, strict codesign, compiled five-language strings and screenshots were inspected, not just prior reports. All 20 existing outbox keys and every other pre-existing catalog entry are unchanged; compiled values match the source for all 22 advisory/outbox keys in all five locales. Backend, web and flame assets have no diff from the reviewed baseline.

Independent artifacts: scratch `catalog-independent-python.log`, `catalog-independent-core.log`, `catalog-independent-ui.log`, `catalog-independent-ui.xcresult`. Existing upstream catalog failure class remains **unknown**. Apple upload evidence will be recorded after the explicit existing workflow completes; upload alone does not establish processing or device availability.

## Original candidate scope / baseline (before release review)

Isolated worktree `/Users/tinyserve/Projects/KeineMagie-catalog-advisory`, branch `candidate/native-catalog-advisory`, created from freshly fetched `origin/main` at documentation commit `468ff5a9062a64649d551ef5f0a7c94168a83138`. Release source is `4d67f4dabf58807bbe9fa3d2f35b316917a91175`, documented Apple upload build `2738.57.39`. Original dirty KeineMagie worktree and pending Diktat were neither read for source nor modified. No push, deployment, credential replay, real inference, login, or reconnect performed.

## Evidence and cause

- User screenshot shows empty text, disabled Translate and the red catalog message. Empty text alone explains the disabled control; the image does not establish a catalog gate.
- Running `tinyserve-keinemagie-1` image is exactly `sha256:c82d870356cefa242bbfd873bc2b5fb50d44ccaee7592e9b6639f41844423cc4`, OCI revision `4d67f4dabf58807bbe9fa3d2f35b316917a91175`, start `2026-11-13T20:11:07.802152815Z`. Public HTTPS health returned 200; unauthenticated `/v1/provider` returned 401.
- Bounded existing backend logs: at most 1,500 lines from the last 24 hours; 131 lines observed before public probes, three provider reads. Only allowlisted method/path/timestamp/duration extracted: `2026-11-14T07:17:58.263140643Z` 310.695067ms, `07:18:32.036347058Z` 127.257481ms, `07:18:49.479842434Z` 157.917792ms. These logs contain no upstream HTTP status/error class. No raw logs, account identifiers, tokens, request text, or credential store contents were emitted.
- Backend `provider.go` loads the saved credential and calls the catalog with its saved access token, intentionally without refresh on advisory status. The catalog path maps non-200, transport, decoding, oversized body and empty visible models to the same `connected:true/catalog_unavailable`. Thus an expired access token is a plausible cause but NOT proven. Neither upstream 401/403 nor schema failure nor another specific live catalog failure can be established from the available logs. The observed fast calls do not prove the particular screenshot's request or its failure class. **This candidate does not claim to repair the upstream catalog.**
- Proven native defect: `refreshTranslator()` copied `catalog_unavailable.message` into shared `translatorError`, and `TranslatorView` renders that as red `ErrorNotice`. A later passive refresh restores the warning even after a successful translation. HTTP/timeout status errors also used the translation-error channel. Existing native outbox submissions already bypass catalog gating, and backend idempotent submissions use their preferred model directly after independent authorization.
- Additional proven error-class defect: an application-level provider-status HTTP 401 was presented as a generic connection error without rejecting identity. This differs from an upstream catalog 401 wrapped in a successful connected/advisory response.

## Candidate behavior

- Separate `providerDiagnostic` from `translatorError`. Catalog unavailable and status transport errors become fixed localized neutral copy, not raw server text.
- Render the diagnostic only inside ChatGPT connection settings. Add a signed-in Settings → ChatGPT route: Release UI inspection showed the existing child translator toolbar Account item is absent on this runtime, making a settings-scoped diagnostic otherwise inaccessible for connected users. No editor/control layout changes.
- Preserve stored connected status on transient status failure. Keep verified disconnection distinct. Application-level HTTP 401 rejects identity and resets private in-memory content.
- Real failed translation remains on its outbox item with its reason and retry/recovery controls. Drafts, key/owner headers, queue algorithm and backend idempotency unchanged.
- No backend code, model selection, OAuth flow, quotas, Diktat, or deployed behavior changed.

## RED → GREEN and verification

All API transports in tests are synthetic, using the actual AppModel/APIClient and actual Go HTTP handlers. They are not production inference evidence.

- Initial AppModel reproduction: two expected failures for red error before submission and its return after successful submission; 39 tests. Candidate passed that loop.
- Expanded reproduction: timeout becomes red; provider HTTP 401 retains private state. Candidate now passes **42 AppModel lifecycle/dataset/learning tests**. Counts assert typing sends zero requests; explicit translate sends one; genuine 424 failure stays failed/provider; 401 invalidates identity; disconnected remains distinct.
- Python native CI discovery: **48 tests, OK, one pre-existing skip**, including the AppModel harness. New settings/localization contracts went red before implementation.
- Swift Core: **68 tests passed**.
- Full `go test ./...`: passed. Targeted race tests for catalog failure, native/browser owner contract, session readiness, held-catalog/idempotency and receipt capacity passed. Existing handler contract covers upstream 401/403/500 preserving stored connection and withholding models without disclosing bodies.
- Ad-hoc signed **Release simulator UI: 5 tests, zero failures** (2 new catalog tests plus all 3 outbox UI tests). Checks empty disabled versus typed enabled; editor/direction/submit rectangle equality before/after catalog failure; synthetic success despite catalog unavailable/timeout; settings-only diagnostic; real request failure visible; offline relaunch, lost acknowledgement, held verification and 401 privacy.
- Exported and visually inspected settings, completed-translation, and failed-queue screenshots. Diagnostic is gray; genuine failed item, retained draft and retry remain visible. Settings screenshot was taken during its own recheck, so the disabled check button/spinner are transient, not a new gate.
- `codesign --verify --deep --strict` passed. Both new keys and existing `outbox.retry` verified in compiled de/en/ru/es/fr app tables.
- `git diff --check` passed. New UI test actor warnings were removed with `@MainActor`; existing UI test actor warnings and missing-AppIntents metadata warning remain outside this fix.

## Artifacts / caveats

Scratch prefix: `/Users/tinyserve/.hermes/cache/scratch/`.

- `catalog-app-red.log`, `catalog-app-red2.log`, `catalog-app-green1.log`, `catalog-app-green2.log`
- `catalog-surface-red.log`, `catalog-settings-red.log`, `catalog-python-final.log`, `catalog-core-tests.log`, `catalog-go-tests.log`
- Final Release result: `catalog-release-ui-green.xcresult`; log `catalog-release-ui-green.log`; built app `catalog-release-derived/Build/Products/Release-iphonesimulator/KeineMagie.app`
- Final screenshots: `catalog-release-green-shots/manifest.json` maps filenames to tests/scenes.
- Initial Release run caught a local generation pitfall: the older `localization_data.py` omits 20 already-shipped outbox keys; regenerating the full catalog removed them and broke UI label tests. Reverted that generated file and applied only the two new catalog entries, preserving all release keys byte-for-byte elsewhere. The final candidate does not include those deletions. Do not run the old full generator without first reconciling its pre-existing source gap.
- Original first-run result `catalog-release-ui.xcresult` is failed evidence, not the final result. Its Account-navigation failure motivated the tested Settings route.
- Actual current user's upstream catalog failure class remains unknown. No live catalog fix, live translation, TestFlight availability, or physical-device installation is claimed. A future authorized diagnostic release could log only fixed phase/error class/upstream status; never refresh/replay stored credentials merely to diagnose a passive warning.
