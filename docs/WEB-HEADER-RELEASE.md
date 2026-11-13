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

Pending scoped source publication, existing documented backend-only local arm64 Compose deployment, and exact public asset/health/data readback. Preserve worker, merged config, mounts, routing and all durable data; do not restore old data during image rollback. Public guest verification does not establish a live private-account check.
