# Direct ChatGPT login: SFSafariViewController loopback evidence

## Corrected conclusion

The earlier categorical iOS blocker was too broad. `ASWebAuthenticationSession` does not expose an HTTP-loopback callback constructor; that says nothing decisive about a separately owned `NWListener` while **SFSafariViewController is presented inside the active app**. External Safari suspension and in-app Safari are different lifecycle topologies.

A real iOS 27.2 Simulator run now proves local browser-process → application-listener transport, including a local HTML redirect and a second test using the production `OAuthLoopback` implementation. This is **not** real OpenAI consent, physical-device proof, or provider endorsement of the self-hosted callback bridge.

## Reproducible evidence

See [`spikes/001-ios-safari-loopback`](../spikes/001-ios-safari-loopback/README.md). Xcode 27.2, booted iPhone 18 Pro / iOS 27.2, simulator UUID `E3277EBA-C768-4357-ACC0-CFAB3EF88518`.

Actual XCUITest results: **4 tests passed**:
- Local consent-test HTML in SFSafariViewController redirects to exact HTTP `127.0.0.1:<random-port>/auth/callback`; callback observed with `UIApplication.applicationState == .active`.
- Production `OAuthLoopback` receives a Safari request and reports `PRODUCTION CALLBACK active=true`.
- Browser Close invokes cancellation and closes the spike listener.
- Five-second spike expiry closes browser and listener.

Screenshots and xcodebuild output are retained under the spike's `evidence/`. Original result bundles remain in `/Users/tinyserve/.hermes/cache/scratch/km-safari-loopback/{final,production}.xcresult`. Browser accessibility evidence from the earlier diagnostic run showed a separate browser UI PID and separate `WebViewProcessID`, not an embedded app-owned WKWebView. No cookies or login pages were inspected, and no provider page was automated.

The initial red callback test failed before listener implementation. The cancellation test then exposed a simulator automation quirk: iOS 27.2 labels the button **Close**, and its center overlaps the address field hit region. Tapping its left-side coordinate exercised the actual Close control; all four final tests passed.

## Native candidate implementation

The translator-first landing screen is preserved. **Continue with ChatGPT** now starts the listener, creates the existing server bootstrap attempt, calls `/v1/provider/bootstrap/start` with its exact callback URI, validates the returned authorization URL, presents SFSafariViewController, forwards the one-shot callback to `/v1/provider/bootstrap/complete`, then refreshes actual provider status. There is no CLI/code-copy requirement in this native path.

Native constraints:
- Bind IPv4 `127.0.0.1` only, ephemeral port, fixed `/auth/callback`.
- Open only `https://auth.openai.com/api/accounts/authorize`, no userinfo/fragment/port or duplicate parameters, exact decoded redirect match and nonempty state.
- GET + HTTP/1.1 + exact Host/path, unique callback parameters, expected state, bounded 8 KiB headers, eight connections maximum, five-second per-connection header deadline, 280-second overall deadline.
- One callback only; listener/socket cleanup on success, expiry, task cancellation, browser Close/swipe dismissal, background, logout/server change and generation replacement. No indefinite background task.
- Session generation and per-attempt UUID checks before opening Safari, before completion, and before changing state. Cancel cannot allow an old async response to open a new sheet.
- No authorization URL, bootstrap token, callback query, PKCE or provider tokens logged. Native errors use localized non-sensitive messages. Provider tokens and PKCE remain server-side; no WKWebView, cookie injection/inspection, private API or paid fallback.

Local cancellation closes the transport, but an unused server bootstrap capability may remain until its five-minute expiry or until next connect/disconnect/logout invalidates it. Cancellation does not undo a code exchange that the server has already accepted; logout still revokes the initiating session. A definitive user-visible success requires the server's credential validation and connected status, not merely socket receipt.

## Provider and release gate

Current official sources inspected:
- [OSS sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in.md): listener first; exact loopback URI, fresh state/nonce/PKCE, initially `dynamic_agent_client`, issued client ID at exchange, signed identity and granted `chatgpt.tokens.use.direct` validation.
- [Self-hosted VMs](https://developers.openai.com/siwc/token-sharing-open-source/self-hosted-vms.md): explicitly documents local OAuth and protected-credential transfer. Server-held PKCE + native callback forwarding remains an unverified provider topology, not an assertion of official approval.
- [Models](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference.md) and [sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions.md): account catalog, server-owned refresh/revocation, public Responses API with `store=false`/`stream=true`.

Next gate is a **user-operated real OpenAI sign-in on a physical iPhone/TestFlight candidate**, with working production HTTPS and provider key configuration. Exercise long human/MFA consent, provider redirect acceptance, successful server validation/catalog and one explicitly authorized translation, denial, background, timeout, duplicate/late callback, logout and server-switch races. No real consent or inference was attempted here. Website commercial HTTPS login, if chosen separately, still needs the relevant OpenAI registration/plan-use approval; that is not proof this OSS Safari topology is impossible.

## Verification scope

32 Swift core tests and 30 Python native CI tests pass, plus existing Go tests. Native Release simulator build succeeded with ad-hoc signing, passed strict deep codesign verification, and was installed/launched on the booted simulator. Generic iOS device Release compilation succeeded with signing disabled; neither is an uploaded TestFlight build. Core tests exercise real sockets for success, one-shot callback, cancellation and timeout; parser/trust tests reject malformed state/method/host/path/duplicate/oversize input. Python checks cover wiring and five-language completeness; they are source contracts, not authenticated native UI race tests. Full AppModel network-race UI tests and physical/provider acceptance remain required before production claims. No commit, push, deployment or consent automation.
