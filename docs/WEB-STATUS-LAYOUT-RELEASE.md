# Stable web status layout and accepted-result recovery

## Scope and causes

Web-only release from an isolated worktree based on `origin/main` (`df309d4`). The dirty main-worktree Diktat work, native outbox candidate, server/worker, official Apple images and hostname are excluded.

1. Apple pending feedback was a newly displayed flex child between the Apple and iPhone buttons. It increased dialog height, recentered the dialog and moved both actions. Pending feedback now shares the existing secondary-action grid track with iPhone pairing. Both localized labels contribute intrinsic sizing even when invisible, so narrow/enlarged text does not create a new row. The Apple artwork is untouched; `aria-busy`, live status, reduced motion, cancellation, timeout and Back handling remain.
2. The translator's connection notice was inserted/removed above the language direction and editors. Guest-only mobile sizing and toolbar overrides caused an additional identity-resolution jump. Checks are now quiet; actionable connection notices sit below the editor and primary controls, and the editor/toolbar footprint no longer changes with identity. No large permanent empty status area. Validated in-memory identity plus CSRF permits an explicit translation attempt without waiting for auxiliary provider/model discovery. The server remains the authorization/provider authority. Cold unknown identity stays locked; existing owner-change/401/logout clearing stays enforced. No web offline queue is introduced.
3. The broad translation catch covered request, validation, record rendering and history rendering. Any client exception was reported as “No server connection or invalid response,” including after a successful saved result. Read-only production investigation observed successful HTTP 201 responses for the reported attempts; it did **not** establish the exact client exception. Normal released-source 201 fixture rendering works; injected DOM exceptions reproduce the misleading error. This release retains accepted owner-scoped record/history before fallible DOM updates, gives localized saved-result recovery without repeating AI, and distinguishes invalid response from a render failure. Browser-console diagnostics contain only fixed phase, bounded error class, numeric HTTP status and a locally generated random attempt UUID—no exception message, response header, text, record or owner. No remote diagnostic upload. A UUID is local diagnostic correlation, not a server request ID.

Independent review also identified stale history and stale request-finally races: a pre-POST history response must not erase a newly accepted result, and an old owner's completion must not release a new owner's busy/controller state. Both now have deterministic regressions.

## Verification

All private/authenticated browser evidence is synthetic, served from actual shipped HTTP assets in Chromium, never owner credentials/provider replay or real inference.

- `status_geometry_browser.py`: RED observed both original bounding-rectangle failures before changes; GREEN **520 checks**, five locales, widths 320/390/1440 and 150% text at 320, held session/provider, initial/refresh connected/disconnected/network/session errors, unchanged editor/control rectangles, focus/selection/draft retention, CSRF POST while catalog held, owner clearing, Apple pending/cancel/reduced motion.
- `translation_response_browser.py`: RED missing recovery after injected accepted-result rendering failure; GREEN **76 checks**, all five locales for record/history exceptions, exact accepted text/history retained, stale held history response, one POST only, safe diagnostics, malformed JSON/schema, network, 401, 502 and ordinary 201.
- Existing sign-in **205**, header **104**, clipboard **22**, HTTP i18n **24**, Coach HTTP browser passed. Node **79 tests** (prior 76 plus metadata, stale-owner request and edited-draft/history race regressions). Go tests/vet passed; backend source unchanged.
- The old flattened `run_legacy_browser.py` runner has six pre-existing failures on both clean `origin/main` archive and candidate (obsolete Coach expectation, missing `mountCoach`, flattened-module syntax); podcast case passes on both. These are not claimed green. Actual HTTP suites above replace the stale runner as release evidence.
- Independent review required fixes for both async races and removal of response-header diagnostic content. Final review recorded with release readback.
- Evidence: `/Users/tinyserve/.hermes/cache/scratch/km-geometry-evidence/`, including `geometry.json`, Apple and translator screenshots; logs `km-geometry*.log`, `km-response*.log`. Representative mobile screenshots inspected.

## Release readback

Pending source commit, CI, backend-only clean-archive deployment and public asset verification. No release is claimed by this section until those readbacks are recorded.
