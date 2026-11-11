# Web provider status diagnosis (local candidate; not deployed)

## Verified contract and cause

`GET /v1/provider` already supports browser cookies: `browserAuth.wrap` validates the browser-kind cookie and injects its bearer internally. Native bearer access is unchanged; browser-kind bearer alone is rejected. No additional web-provider route or auth bypass is needed. Browser mutations retain exact Origin plus cookie-bound CSRF.

The lean `/v1/web/session` intentionally returns local identity/CSRF/expiry only. The web shell nevertheless classified missing provider state as `provider-required`, displayed a connect instruction before discovery completed, and discarded same-owner verified provider state on every identity refresh. Its explicit account recheck called only session restoration: on the podcasts route with the dialog closed it did not fetch provider at all. Existing tests usually embedded provider in synthetic session responses, masking this real-contract regression.

The candidate distinguishes unknown/loading from verified disconnection, retains verified state only for the same validated owner, explicitly fetches the catalog on manual recheck, coalesces pending requests, and bounds provider transport to eight seconds. Network/invalid-response errors remain unknown with retry, rather than asserting disconnected or enabling translation/reconnect. Translation requires verified connected plus nonempty selected_model and no active verification/error. Actual provider HTTP 401 still clears private identity; upstream catalog 401 is handled server-side as HTTP 200 connected/catalog_unavailable and does not expire Apple identity.

## Strictly read-only live audit

Only anonymous counts/booleans were emitted; no live browser cookie was obtained or replayed. The distroless container has no cat, so archive streams from `docker cp ... -` were processed in memory (no extracted credentials/files). The encrypted owner record was decrypted in memory only to inspect presence/expiry metadata, without refreshing or calling provider status.

- One persisted owner; one active native session and one active browser session.
- Native/browser owner sets equal, exactly one shared owner.
- One nonempty encrypted provider record, belonging to that shared owner.
- Record decryptable, access and refresh present; access token not expired and outside the one-minute refresh window at inspection.

This does **not** establish upstream credential validity or a currently offered model. No authenticated live status/catalog request was made, no reconnect/disconnect or inference was initiated, and no paid fallback was used. The signed-in production UI remains a user-assisted verification gate after deployment.

## Verification

Two regression tests were observed failing before the fix: manual recheck on lean identity never called `/v1/provider`, and delayed provider discovery showed `ChatGPT im Konto verbinden.`.

- Real signed synthetic Apple JWT/code callback -> real browser cookie -> same-owner native/provider integration passed, including browser GET without Origin, offered model, upstream catalog 401 preservation, other-owner isolation, missing mutation CSRF denial, browser bearer denial, expired/guest cookie denial.
- Targeted Go provider tests passed under race detector; go vet passed.
- Whole current web Node suite: 52 passed.
- Actual shipped modules in browser with synthetic delayed identity/history/provider APIs: 12 passed, including unknown/loading and independent provider resolution, 401 clearing, coalescing and timeout recovery. This about:blank fixture does not claim live identity, HTTP CSP/image enforcement or real upstream account acceptance.

Concurrent episode/learning changes were not overwritten; their module dependencies were included in the fixture harnesses. No commit, push or deployment performed by this diagnosis.
