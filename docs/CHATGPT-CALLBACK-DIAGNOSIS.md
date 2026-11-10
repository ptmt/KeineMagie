# iOS callback completion diagnosis (2026-11-10)

## Production evidence — read-only, no provider requests

Inspected the running `tinyserve-keinemagie-1` container, its actual mount paths,
source-defined auth/provider schema, and bounded logs (30 minutes, max 300 lines).
Only counts, booleans and endpoint/duration metadata were emitted; no identities,
sessions, callbacks, claims, keys or credential contents were emitted or saved.
A temporary local Go metadata reader used `docker cp ... -` in memory; it did not
invoke server handlers, create sessions, refresh credentials or call inference.

- Auth store: one owner, two unexpired application sessions.
- `/app/data/providers`: **zero encrypted credential records**; the owner has no
  persisted provider record. Therefore the observed consent did **not** establish
  a durable ChatGPT connection at inspection time. This is not a working-grant claim.
- Bounded current-container logs contained one bootstrap start and one complete.
  Complete took `497.481794ms`; existing logging records method/path/duration only,
  **not HTTP status or failure stage**. It cannot distinguish interrupted exchange,
  token grant/JWT/scope rejection, or registration failure. No unsafe OAuth replay
  or real code exchange was performed to resolve that ambiguity.

## Reproduced native fault

AppModel clears `chatGPTBrowser` immediately before awaiting bootstrap complete.
The sheet's nil setter previously called `cancelChatGPT` unconditionally, clearing
connection identity and canceling the retained network task. A programmatic browser
close could therefore cancel a legitimate exchange and suppress both the eventual
provider refresh and its error. The exact delayed-complete regression ran real
AppModel/API/loopback code and failed with busy false and no published connection.
After separating browser dismissal from cancellation/normal cleanup it passes.
Explicit user close while browsing and explicit cancellation during exchange still
cancel; late results are suppressed. Safari delegate events carry browser identity.

## Additional connection-state repairs

- Provider refresh now publishes status before requesting history, so history failure
  cannot hide a known saved connection. Refresh exposes a busy indicator and safe
  HTTP/format errors; completion failures survive programmatic dismissal.
- Catalog discovery failure formerly returned HTTP 502 and discarded connection
  fields despite a saved accessible credential. It now returns `catalog_unavailable`,
  connected true, no models/selected model. Native UI warns and disables translation
  without an offered model. This does not assert upstream authorization is valid.
- Synthetic signed server OAuth now exercises complete -> persisted credential ->
  status/catalog -> owner history without invoking external APIs or inference.

## Verification and release boundary

- Seven executable AppModel lifecycle cases pass (real IPv4 loopback; synthetic
  transport; Keychain stub traps accidental access).
- 41 core Swift tests pass; server `go test -race ./...` passes.
- iOS Simulator xcodebuild succeeds (build-only; no device provisioning claim).
- Changes are local, uncommitted and undeployed. A physical-device retry with a new
  shipped build is still required. Production's exact complete failure stage remains
  unknown because the existing logs lack status metadata; do not call it proven
  exchange cancellation solely from browser dismissal.
