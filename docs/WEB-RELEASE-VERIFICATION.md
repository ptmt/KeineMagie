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

## Deployed and verified

- Source commit: `806a6cd698bd9ffcae2c736b2f7b89faf6fd17fb`, pushed to main. Backend built from a clean `git archive` of exactly that commit; local image `sha256:2323ad95a9423d049bb599560ba347b4e2fb86264ce9c61b6f263a38776fb611` is running. Server publication CI [43022700662](https://github.com/ptmt/KeineMagie/actions/runs/43022700662) completed **success**, including Build image. No TestFlight run was triggered.
- Backend-only replacement through the established base + durable Compose override. Worker image `a61794a3d7e7…`, worker container ID and all unrelated container IDs remained unchanged. Full semantic resources/mounts/networks/environment/routing comparison passed. New image revision label is expected metadata, not a routing change.
- Authoritative locked pre-stop state was **completed**, one job, one subscription, **2113 source segments and 2113 translations**: the user's retry had finished before this release. No retry/reset/provider inference was initiated here. Six nonruntime data files were byte-identical across this idle deployment; this does not claim they were unchanged since the prior failed-job audit.
- Protected backup directory `deployment/release-web-20261111T124421Z/` is 0700; archives and private inspection/hash records are 0600. No user data was deleted. Local ignored generated test data and untracked spikes were excluded, not removed.
- Public HTTPS health **200**; all **15** runtime assets fetched and SHA-256/bytes matched the exact source commit (including actual app module, episode modules/CSS, both locale modules, all Apple artwork). Eight protected guest endpoints returned **401**, four non-allowlisted/private paths **404**, clean nested reader URL **200** with exactly the public shell. Public no-store/CSP headers retained.
- Actual production guest browser changed selector to Russian, persisted it across real navigation/reload, rendered Russian navigation, and kept private content empty and translator disabled. No owner cookie was used.
- The first public post-replacement probe briefly returned **504**; edge-network application health was 200 and subsequent public IPv4/default TLS probes passed without infrastructure changes. Verification helper initially rejected the new image revision label and a stricter no-store header; corrected checks compare semantic routing labels and require the no-store directive, preserving additional proxy no-cache directives.

Remaining gate: signed-in live provider rendering and generated-language quality require user-assisted verification. No real-account inference was initiated by these tests, and fixture results/public health do not establish upstream provider validity or language quality. Manual Compose lifecycle caveat remains; CI publication is separate from the locally exact-commit image deployed here.
