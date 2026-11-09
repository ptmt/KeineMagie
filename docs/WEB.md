# KeineMagie browser login and translator

## Direct Apple web sign-in

The browser button starts a same-origin CSRF-protected `POST /v1/auth/apple/start`, then navigates to Apple. The exact registered return URL is **https://keinemagie.tinyserve.org/v1/auth/apple/callback** (no trailing slash). No native session, Apple token or application token is placed in browser storage or a redirect URL. The callback redirects to `/` after issuing a separate browser session.

### Apple Developer setup (user-managed)

1. Use Apple Developer team **49PJNAT2WC**. Under Identifiers, ensure the native App ID **de.keinemagie.app** has Sign in with Apple enabled. Preserve its existing primary-app grouping; if it is already grouped, use that same primary App ID throughout.
2. Register/select the Services ID **de.keinemagie.web** (provided by the user, not the native bundle identifier). Enable Sign in with Apple → Configure → select the **same primary App ID as the native app**. This association is essential for the same Apple subject/account across web and native. The server only links verified issuer + subject; it never links by email, including private relay email. Incorrect grouping can create a separate account; do not try to repair that with email matching.
3. Website domain/subdomain: **keinemagie.tinyserve.org** (no scheme/path). Return URL: **https://keinemagie.tinyserve.org/v1/auth/apple/callback**. Click Done, Continue and Save. Apple currently says no domain-verification file upload is required for this registration.
4. Under Keys, create/select a key with **Sign in with Apple**, configured for that same primary App ID. Download the `.p8` once and install it through a secure local/server channel, never chat or source control. Record its Key ID. The user's current candidate Key ID is **2LC369M628**, inferred from its uploaded filename, not confirmed against Developer portal metadata. The user authorized testing this candidate; it has been exposed through chat, so rotation is still recommended. Do not automatically revoke it. A local parse cannot prove Apple capability, grouping, Key ID or registration.

Server-only environment (there are deliberately no web defaults for these four values):

```dotenv
APPLE_CLIENT_ID=de.keinemagie.app
APPLE_WEB_CLIENT_ID=de.keinemagie.web
APPLE_TEAM_ID=49PJNAT2WC
APPLE_KEY_ID=2LC369M628
APPLE_PRIVATE_KEY_FILE=/run/secrets/keinemagie-apple.p8
WEB_ORIGIN=https://keinemagie.tinyserve.org
```

`APPLE_CLIENT_ID` remains the **native** audience. `APPLE_WEB_CLIENT_ID` is separately validated for web ID tokens. The callback is fixed in code, not configurable/derived from a request. All four web values must be present; incomplete config keeps `apple_available:false` and app approval available. A complete but invalid configuration, unreadable/non-P256/non-PKCS8 key or group/world-readable key fails startup. The key file must be a private regular file (0600 or stricter), outside the repository, readable by the runtime account; it is loaded only into server memory. No private key contents, client-secret JWT, authorization code or Apple response bodies are logged.

For the existing nonroot Docker runtime (UID 65532), securely install a dedicated server copy owned by UID 65532, mode 0600, then bind mount it read-only at `/run/secrets/keinemagie-apple.p8`; do **not** loosen permissions or bake it into the image. Example mount: `--mount type=bind,src=/secure/keinemagie/AuthKey_2LC369M628.p8,dst=/run/secrets/keinemagie-apple.p8,readonly`. Set the environment above explicitly and retain the existing persistent auth/history volume. The local candidate is at `/Users/tinyserve/Library/Application Support/tinyserve/secrets/keinemagie/AuthKey_2LC369M628.p8`; do not copy it into this repository. Deployment and real consent are separate acceptance steps, not performed by these tests.

### Callback security and protocol

- Start requires the bootstrap pairing cookie, exact Origin, `X-CSRF-Token`, and rejects cross-site Fetch Metadata. GET cannot start login. Response JSON contains only the Apple authorization URL (`response_type=code`, `response_mode=form_post`, independent random state/nonce); the frontend validates the Apple origin/path before navigating.
- `__Host-km-apple`: dedicated 256-bit browser secret, Secure, HttpOnly, **SameSite=None**, Path=/, no Domain, five-minute lifetime. A Strict/Lax cookie would not reliably arrive on Apple's cross-site POST. Server state stores its hash plus state, nonce, expiration and consumption marker; max 1024 live transactions, endpoint/direct-peer limits, expiry/restart invalidation. A new attempt in that browser replaces its old transaction.
- Only `POST /v1/auth/apple/callback` accepts the cross-site Apple form. Missing Origin is allowed for compatible user agents, but a supplied Origin must be exactly `https://appleid.apple.com`; neither this header nor any posted ID token authenticates a user. Require bounded URL-encoded body, no query parameters/duplicate security fields, matching live browser-secret + state. Mark used atomically **before** exchange (including cancel/error), reject replay/concurrent consumption. Failed binding does not consume another browser's attempt. Logout cancels an outstanding transaction and deletes its cookie.
- Exchange the one-time code directly at Apple's fixed HTTPS token endpoint with exact callback, Services ID and a five-minute **ES256** client-secret JWT signed with the P-256 `.p8` (`kid`, team issuer, Services ID subject, Apple audience). No redirects; bounded response and ten-second exchange context. Apple access/refresh tokens are discarded, not stored.
- Verify the exchanged ID token with Apple's fixed JWKS endpoint: **RS256**, exact Apple issuer, singleton Services ID audience, issued-at/expiry, nonempty subject and transaction nonce. Native verification remains unchanged. Mint a hashed, durable 24-hour `kind:browser` session using the same subject namespace as native login. Session cookie remains **SameSite=Strict**, Secure, HttpOnly. Clear transaction/bootstrap cookies, redirect to `/`; the page restores session via same-origin fetch. No callback exception is added to ordinary mutation Origin/CSRF middleware.
- Apple’s current [authorize contract](https://developer.apple.com/documentation/signinwithapplerestapi/request-an-authorization-to-the-sign-in-with-apple-server.), [token contract](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens), and [OIDC discovery](https://appleid.apple.com/.well-known/openid-configuration) do **not** document/advertise PKCE parameters or challenge methods. Therefore this confidential-client integration does not send unsupported PKCE parameters or claim PKCE enforcement. It uses authenticated server code exchange plus browser-bound state/nonce.
- Apple references: [web registration](https://developer.apple.com/help/account/capabilities/configure-sign-in-with-apple-for-the-web), [grouping](https://developer.apple.com/help/account/capabilities/group-apps-for-sign-in-with-apple/), [client-secret fields](https://developer.apple.com/documentation/accountorganizationaldatasharing/creating-a-client-secret).

## Alternative: approval in the signed-in iOS app

No Apple Services ID configuration is required for this deliberate alternative. The existing native Apple identity remains authoritative; the browser gets a **different application session**, never the native token.

1. Serve the Go service and the public web assets on the same HTTPS origin. Set `WEB_ORIGIN` to that exact origin (default `https://keinemagie.tinyserve.org`). Ship the updated iOS app too.
2. In the browser: Konto → Mit iPhone anmelden. Leave the displayed five-minute code open.
3. In the authenticated iOS app: Browser verbinden → enter code → Anfrage prüfen. Check the displayed origin and code. Read the warning, then explicitly **Genehmigen** or **Ablehnen**. Never approve someone else's code.
4. This browser polls every three seconds and receives a new Secure HttpOnly cookie after approval. Personal history and provider status belong to the same Apple account. Logging out revokes only this browser session and clears its cookies.
5. To connect ChatGPT: browser Konto → Continue with ChatGPT. Copy the short-lived **provider connection code** into the local desktop helper, not into chat:

   ```sh
   cd /Users/tinyserve/Projects/KeineMagie/server
   go run . connect
   ```

   Enter the HTTPS server origin, then the provider connection code at the prompts. The helper opens official consent and listens only on `127.0.0.1`. After consent, choose Verbindung erneut prüfen. This is separate from the short browser-pairing code. A real ChatGPT consent/translation has **not** been verified by local pairing tests. No shared paid API fallback is authorized or used for account sessions.

## HTTP contract

- `GET /v1/web/config`: `apple_available` reflects complete locally validated Apple web configuration, `pairing_available:true`, `csrf_token`, `chatgpt_connect_available` (only with server encryption key configured). Creates a five-minute `__Host-km-pairing` secret cookie if absent. No secret in JSON. Bootstrap CSRF stays memory-only. Cross-site bootstrap fetches are rejected.
- `POST /v1/web/pairing/start`: empty JSON, exact Origin and `X-CSRF-Token`. Returns `{user_code:"ABCD-EFGH",expires_in:300,interval:3}`. Replaces this browser's earlier attempt. Five creations per direct-peer minute; bounded active map 1024.
- `POST /v1/web/pairing/poll`: same browser cookie, bootstrap CSRF and Origin; empty JSON. `202 {status:"pending"}`; `200 {status:"approved"}` sets a new `__Host-km-session` and removes pairing cookie. Invalid/denied/expired/consumed attempts return generic 404. Minimum three-second interval, at most 100 polls, five-minute lifetime, endpoint limit 100 per direct-peer minute.
- Native only: `POST /v1/auth/browser/inspect {user_code}` authenticates the existing native bearer, claims the code for that session/account, and returns `{approval_token,user_code,origin,expires_at}`. No approval happens here. `POST /v1/auth/browser/approve {approval_token,approve:true|false}` requires that exact original native session; explicit one-time decision. Browser sessions and requests carrying Origin cannot use these routes. Inspection/decision attempts limited to ten per direct-peer minute per endpoint. Unknown/claimed/expired code responses do not expose a user identity.
- `GET /v1/web/session`: `200 {user:{id},csrf_token,provider,expires_at}`, 401 if signed out. Provider object is produced by the existing per-account `/v1/provider` handler. No session token in JSON.
- `POST /v1/web/logout`: exact Origin and session `X-CSRF-Token`, revokes server hash, expires cookies, 204. GET never logs out.
- `/v1/provider`, `/v1/provider/connect`, `/v1/provider/disconnect`, `/v1/translations`: browser cookie authentication; **all mutations** require exact Origin and session CSRF. Native bearer contracts remain unchanged. Never fall back to legacy shared history or API credentials for browser requests. Provider bootstrap endpoints use their separately bound one-time capability, not ambient cookie authority.

Both cookies use `__Host-`, Secure, HttpOnly, SameSite=Strict, Path=/, no Domain. Pairing secret has 256 random bits; user code has 40 random bits with an unambiguous alphabet. Server stores only the pairing-secret hash. Preview capability and native session remain server-side/native-only. Pairing approvals are process-local, mutex-protected, atomically consumed before durable session minting and invalidated on restart. The existing file-locked auth store persists only a hash of the distinct browser token, a `kind:browser` marker, user ID, and 24-hour expiration. Parent native session is rechecked atomically at mint. Browser logout does not revoke native login; later native logout does not implicitly revoke an already-issued distinct browser session.

## Server deployment

From repository root: `docker build -f server/Dockerfile -t keinemagie .`. CI uses the root context and triggers on server or web changes. The runtime copies **only** `index.html`, `app.mjs`, `core.mjs`, `styles.css`, `favicon.svg` into `/app/web`; `WEB_ASSET_DIR=/app/web`. Local `cd server && go run .` defaults to `../web`. An explicit URL allowlist serves these files, never tests, source, environment or data. CSP includes frame-ancestors none; nosniff, no-referrer and no-store are set. HTTPS/HSTS belong at the production reverse proxy. `.dockerignore` excludes native builds, data and credentials from the build context.

Required for provider consent: mount a persistent, private auth/history/provider data directory and a separate `PROVIDER_KEY_FILE` containing **32 raw random bytes, mode 0600**, readable by runtime UID 65532. Keep that encryption key outside provider data and out of source control; retain it to decrypt refresh credentials. No key means pairing/history still work but provider connect fails closed and is not advertised. Existing provider integration encrypts access/refresh credentials server-side. Set `TRANSLATION_DAILY_ATTEMPTS` (default 100, valid 1–10000); quota file failures or invalid configuration fail closed. One active translation per user across processes, daily UTC attempts persisted before upstream work (failed attempts count), 8000 input characters, 8192 upstream output-token cap, 64 KiB translated text cap and bounded stream. No provider failure falls back to a paid key. Current provider service also serializes upstream work globally; optimization is out of this workstream.

Direct Apple web authorization is implemented behind the configuration gate above; explicit app approval remains an alternative. Neither uses a token-paste shortcut. Complete local configuration cannot establish that Apple Developer registration was saved correctly: a real user consent round-trip and matching native/web account are still required acceptance checks.

## Verification

Verified results for this work: 106 Go tests passed, one opt-in harness skipped in normal runs; race detector and vet passed. Six Node tests, 26 Swift tests and 28 Python native contracts passed. Release simulator build and codesign verification passed; all eight pairing strings are compiled in each of five languages. English/Russian signed-out screens inspected; authenticated native approval UI was compiled but not tapped with a real Apple login. Docker image built and ran as nonroot; real container health/assets returned 200 and source guard returned 404. One benign Xcode AppIntents metadata warning (no AppIntents dependency).

Run `node --test web/tests/*.test.mjs`, `node --check web/app.mjs`, `cd server && go test -race ./... && go vet ./...`, `cd native/Core && swift test`, and native localization contracts. Release simulator build is ad-hoc signed. The opt-in `TestLocalBrowserHarness` creates a clearly synthetic test-native account only when `KM_BROWSER_TEST_DIR` is explicitly set; normal production code has no test-login route.

A real local Chromium browser was exercised against the Go handler at `http://localhost:8897`: Secure cookies were accepted by Chromium's localhost secure-context exception, invisible to document.cookie; real fetch/DOM code displayed the pairing code, a separate synthetic native client inspected and explicitly approved it, the browser restored its account, a missing-CSRF mutation returned 403, logout read-back returned 401 and cookies were absent. No cookie flags were weakened. This proves local transport/UI integration, **not** production TLS, actual Apple consent, actual ChatGPT consent or a completed upstream translation.

Translator is the first workflow. Other tabs remain planned. Enrichment arrays are intentionally empty in the fast adapter; the UI does not invent learning hints. No commits, push or deployment performed as part of this work.
