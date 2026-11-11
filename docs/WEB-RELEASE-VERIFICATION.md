# Web learning release — 2026-11-11

## Scope and verified local gates

Provider discovery now distinguishes unknown/loading from verified disconnection, preserves only same-owner verified state, and explicitly rechecks the real `/v1/provider` contract. The web interface supports DE/EN/RU/ES/FR independently of translation direction. Episode readers add owner-authenticated readable permalinks, quoted vocabulary/favorites, dated self-assessed CEFR/progress, and explicit checkpointed summary/topic/recommendation generation.

- `env -u TRANSLATION_DAILY_ATTEMPTS go test -race ./... -count=1`: passed, 35.836s; unchanged default 100. `env -u TRANSLATION_DAILY_ATTEMPTS go vet ./...`: passed.
- The previously failing `TestTranslationInstructionsContract/account` reproduced HTTP 429 instead of 503. Its missing authPath made quota/account state share `server/data/auth.json`. Both subtests now set explicit TempDir authPath; no quota increase, production change or user-data deletion.
- `node --test web/tests/*.test.mjs`: 60 passed, zero skipped/failed. Node reports its experimental localStorage warning.
- Actual local HTTP Chromium fixtures: i18n 24 checks; episode reader 65 synthetic API requests, zero page errors, responsive 320/390/768/1440, deep URLs/history, clipboard and server profile/vocabulary readback.
- Episode analysis Chromium module fixture: 7 checks, zero page errors: no automatic generation, dated histories, explicit bounded three-step generation, cancellation, explicit resume, navigation cancellation. This fixture injects a synthetic API at the module seam; it is not real provider execution.
- Shipped-DOM session readiness fixture: 12 checks; locale fixture: 13 checks. These use synthetic delayed APIs, not production credentials.
- Backend integration covers full 216,000-character source planning and every segment (not an excerpt), checkpoint recovery/new router, strict completed SSE/schema/citations, shared quota admission and browser CSRF/bearer isolation.

## Security and packaging review

New learning routes and permalink lookup remain owner-scoped; browser-kind bearer alone is rejected, browser mutations require exact Origin and cookie-bound CSRF, API responses are no-store. Browser transport retains same-origin credentials and does not copy owner tokens to localStorage. GET analysis only reads/plans, never calls a provider; explicit Generate/Resume authorizes the displayed bounded remaining plan, with one inference per POST. Unknown level remains unknown rather than inferred promotion.

Static serving and Docker copy use an exact public allowlist including both locale modules, all episode modules/CSS and five official Apple locale images. Nested reader URLs serve only the public shell, never private metadata. Docker context excludes local data/cache/models and spikes. Release artifacts and documentation contain synthetic fixtures/aggregate verification only, not real transcripts or credentials.

## Release status

Local verification complete. Deployment, public asset byte comparison and exact CI handle will be recorded after the scoped source commit is built and deployed. No real-account inference was initiated by these tests. Signed-in live provider rendering and generated-language quality require user-assisted verification after release; do not infer them from synthetic fixtures or public health.
