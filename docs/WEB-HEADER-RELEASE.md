# Stable web identity header

## Cause and scoped fix

Cold `session = null` was rendered as a confirmed guest in both static HTML and `renderConnection()`. When the session resolved, the sign-in label changed to Profile and the previously hidden language selector widened the flex header, moving navigation. Same-owner background refresh already retained identity and drafts; that behavior was preserved rather than replaced with persistent browser auth caching.

The static header now reserves its account/language footprint and hides the account control until identity is known. An in-memory `identityKnown` flag distinguishes unknown from a confirmed guest. Failed cold checks offer the neutral localized Open account control and existing retry; they do not imply signed out. No new spinner, timer or network request. Authenticated refresh retains the verified header and same-owner UI; 401/logout/owner change still erase private content. BFCache retains its fail-closed revalidation. Compact mobile widths retain readable language labels (320px uses the smaller wordmark).

Apple pending feedback/cancel/back recovery, CSRF, 30-day fixed new-session issuance, provider readiness, Coach, native clients and worker behavior are unchanged. No domain migration, owner cookie/provider replay or real inference.

## Reproduction and verification

`web/tests/header_browser.py` serves shipped assets over local HTTP and holds the actual session request in Chromium. Before the fix, deterministic RED: `1440 unknown never shows signed-out account`. GREEN verifies unknown/private gates, exact header rectangles before/after identity, slow same-owner refresh, locale changes while pending, 503 retention, 401 clearing, owner replacement, logout, cold error/retry and BFCache revalidation. All five locales and widths 320/390/768/1440 exercise guest/auth transitions. All authenticated evidence is explicitly synthetic.

- 104 header checks; 205 sign-in checks including immediate pending, coalescing, CSRF, cancellation, timeouts and real browser Back with synthetic Apple destination.
- 76 Node tests; full Go tests/race/vet; HTTP i18n 24 checks; Coach HTTP browser suite passed.
- Independent read-only review found DOM-harness incompatibility and an incorrect history endpoint in the new privacy assertion; both corrected and retested. Final verdict recorded with release readback.
- Existing sign-in browser test had one fixed-100ms route timing flake; replaced that wait with its existing bounded request wait, not a relaxed assertion.
- Desktop and 320/390px screenshots inspected. An initial 44px language field clipped the selected language; widened to 80px and reverified all locales without overflow.
- `git diff --check` and added-line security review passed; no credentials or auth transport changes.

Ephemeral evidence: `/Users/tinyserve/.hermes/cache/scratch/km-header-evidence/` (`1440-` and `390-` initial-delayed, signedin, refresh-fr, guest-fr; also 320/768). Logs `km-header-{browser,signin,node,coach,review-final}.log`.

## Release

Released source **`375b94eaaf4a342c0eaf71e108d2755c5abbbf69`**; [server CI 43469682631](https://github.com/ptmt/KeineMagie/actions/runs/43469682631), build job `132037974653`, **success**. Final independent read-only Codex review: no logic/security blockers. No native upload triggered.

Existing documented backend-only local arm64 Compose workaround used a clean committed archive, not the separately published CI registry image. Running backend **`sha256:44ec731086fc38dca2df69c8c836d030daf1ee7bfd01a0a549847be819f11b4c`**, matching OCI source revision. Worker remains **`sha256:a61794a3d7e74b63d9626c453f3b0bac1b9f9f1351b0bb6349ccf564bded9382`**. Merged configuration changed only backend image; worker/unrelated IDs, environment, resources, mounts, routing and private network unchanged. Backend executable exact SHA256 unchanged from prior image: `a3ac9e86fc8d53f4b06bce032b01a10ddb642047c03e4a3d285de45cdaad7f96`.

Locked preflight and post-replacement readback: **8 nonruntime durable files byte-identical; 0 active jobs, 1 completed job, 1 subscription, 2113 segments and translations**. Private backups and preservation evidence: `deployment/release-header-20261113T170839Z/` under the existing tinyserve service directory. Rollback: previous backend `sha256:031c5cec14b0cb632fef24d5fee97b0f6d36eb106bbfd0cb1feeead290c320cc` and saved `compose.previous.yml`; never restore historical data.

Certificate-validating public HTTPS: **health 200; all 21 runtime assets exact committed bytes/SHA256; session/Coach/podcast APIs 401; private/source paths 404**. Guest `/v1/translations` with exact browser Origin returns 401; a raw no-Origin/no-cookie curl reaches the pre-existing disabled legacy gate (503 `TTS_AUTH_TOKEN is required`), not private history. No security setting was changed to alter this result. Strict CSP/no-store retained.

Real public Chromium guest: five locales × 320/390/768/1440, no horizontal overflow or JS errors, sign-in header visible and language selector hidden; mobile/desktop screenshots inspected (`km-header-evidence/live-guest-{locale}-{width}.png`). Public readback JSON: `km-header-public-verified.json` in scratch. Delayed/authenticated transitions remain synthetic fixtures, **not a live private-account verification**. No owner credentials, provider replay, inference, worker/config/domain migration or protected-data mutation. Untracked spikes, migration plan and Python caches remain excluded.
