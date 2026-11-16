# Web Dictation blank-state investigation

## Reproduced causes, not a presumed stale deployment

Both supplied screenshots were inspected. The Dictation screenshot (heading and `+`, no loading/error/empty text) reproduces with the **current** production module and an ordinary signed-in `200 {"items":[]}` response. `web/dictation.mjs:load` rendered the list while `loading` was true (suppressing the empty state), then cleared `loading` and updated only the status paragraph. The list never rendered again. Fix: render after settling the read; indicate local draft hydration as loading too. Validate the list before replacing valid state, so malformed responses cannot poison later renders. Owner epochs, draft recovery, auth and all explicit paid-action boundaries stay unchanged.

A second independently reproduced rollout hazard uses shell `64b0647` plus current modules: `app.mjs:updateInput` dereferenced absent `result-skeleton`, threw `Cannot set properties of null (setting 'hidden')` before bootstrap, and prevented identity/Dictation startup. Both new Translate presentation nodes are now optional when running with that older shell. Old modules with new HTML remain executable (and reproduce the known old Dictation bug); no automatic reload, cache purge, storage deletion, secret or CSP change is introduced. This proves mixed-version compatibility, **not** that the reporting user's browser had a mixed cache.

The Coach screenshot is compatible with current rendering of **saved historical turns**: old user text `Practice · ~30 sec` and `again` is deliberately preserved verbatim; older answered exercises collapse behind Show answer & feedback, source remains on completed turns, and the newest offer gives the contextual `30 seconds` chip. Current Coach action/DOM suites reproduce these rules. There is no evidence justifying rewriting historical content or claiming stale deployment. Private signed-in production history was not opened.

## HTTP / packaging evidence before patch

Public `/dictation.mjs` SHA256 `d7700eba06c5f774bc450f81234169bfb41344a63731dd5eeb25e25d54180da2` exactly matched clean origin/main `70c4d83` (released code `2d49504`). HTTP 200 JavaScript, Cache-Control contains `no-store`, Cloudflare `DYNAMIC`. Real public guest Chromium loaded all observed module dependencies and all five styles; guest Dictation displayed its sign-in state. Files are an explicit filesystem allowlist copied by Docker, **not Go embed**. No service worker was found in the source/runtime graph; no cache purge was warranted. A public-byte module-graph check accompanies release evidence.

## Regression verification

- `node --test web/tests/*.test.mjs`: includes empty history, malformed history, pending hydration, owner fencing and no autoplay.
- `web/tests/dictation_empty_browser.py`: synthetic validated owner, completed empty list, all five locales, keyboard open/Escape, malformed response, no page exceptions. No provider generation.
- `web/tests/web_release_cache_browser.py`: actual committed old shell/new modules, old modules/new shell, current/current; first case failed before compatibility guard, now passes without JS errors. Old-module test intentionally identifies its known empty-state bug rather than pretending old code is fixed.
- `web/tests/coach_actions_browser.py` and `coach_chat_browser.py`: dynamic actions, progress explicit-only, saved messages/masking/source, draft/keyboard, receipt behavior; synthetic HTTP only.
- Baseline Go failure: `TestNativeFollowupOptionalOwnerWebCompatibilityAndCSRF` expects cross-owner 404 but existing native owner requirement returns fail-closed 403. Reproduces individually on unchanged server sources. No backend auth change made. Remaining `go test -race -skip '^TestNativeFollowupOptionalOwnerWebCompatibilityAndCSRF$' ./... -count=1` and `go vet ./...` pass. Full suite is **not** claimed green.

Original dirty main checkout, native followup and unrelated dashboard work were untouched. No iOS build requested or needed. Release/readback evidence is recorded below once completed.
