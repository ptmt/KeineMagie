# Apple identity + explicit personal ChatGPT connection

## Implemented vertical slice

Native Apple authentication is unchanged: server challenge, signed Apple ID-token verification, opaque hashed 30-day application sessions; native session token remains in Keychain. Session-authenticated translation **never** falls back to legacy shared bearer credentials or `OPENAI_API_KEY`. Legacy endpoints remain available only to explicitly configured legacy clients, not native account sessions.

See [TRANSLATOR-API.md](TRANSLATOR-API.md) for the shared contract. The native account screen now provides DE↔RU text translation, real per-owner history, provider status, local-bootstrap setup and disconnect. Fast translation returns empty enrichment arrays; idioms/grammar/vocabulary generation, audio, dictation, podcast and coach are deliberately not implemented.

## Supported connection shape and explicit consent

The official OSS flow uses dynamic registration (`dynamic_agent_client` **only initially**), a stable host ID, fresh state/nonce/PKCE, and an **HTTP 127.0.0.1 /auth/callback listener on the desktop running the browser**. Issued `oaiapp_…` client ID is saved and reused with validated subject identity. No client secret or paid API key is used. Native iOS and a remote website cannot simply redirect to their remote server in this OSS flow.

The implemented local bootstrap is a public-client loopback **bridge**: the user's desktop owns the browser and callback listener; the authenticated user's server owns pending PKCE/state, code exchange, ID-token/JWKS validation, encrypted credentials and refresh. The short-lived bridge carries a callback/code to that server over HTTPS, not provider tokens to the browser. The official self-hosted-VM recipe instead explicitly describes completing OAuth locally and securely transferring the protected credential record (e.g. SSH). This bridge follows the same OAuth public-client parameters but has **not been approved or live-tested with OpenAI**; do not represent it as a verified mobile/cloud integration or silently replace it with scraped/other-tool credentials. If OpenAI rejects this topology, use the documented local-completion + protected SSH-import design in a follow-up rather than weakening validation.

1. Configure server `PROVIDER_KEY_FILE` with an absolute path to **exactly 32 random raw bytes**, mode `0600`, outside provider data/backups. Example on the server: `umask 077; openssl rand -out /secure/keinemagie-provider.key 32`. Set `PROVIDER_KEY_FILE=/secure/keinemagie-provider.key`. Do not commit, send in chat or log this key. Keep a separately secured backup: loss makes existing encrypted credentials unreadable.
2. Start the Go server normally. It persists its own stable opaque host ID under `<AUTH_PATH directory>/providers/host`.
3. Sign in with Apple on the native app, open **ChatGPT verbinden**, then **Continue with ChatGPT**. Native code starts an ephemeral 127.0.0.1 listener, calls bootstrap start, and presents SFSafariViewController. The callback is forwarded to bootstrap complete; provider tokens/PKCE remain server-side. See [runtime simulator evidence and real-provider gate](CHATGPT-IOS-LOGIN.md). No CLI step is required for this candidate native path.
4. Personally review and approve permissions in the in-app Safari sheet. Real provider consent is still unverified. The optional desktop alternative remains `cd server && go run . connect`, with server HTTPS origin and one-time bootstrap capability via stdin; native UI no longer exposes this secret.
5. Return to the app and tap **Verbindung prüfen**. Only successful signature/issuer/audience/expiry/nonce/subject/scope validation marks the grant usable. Callback replay, wrong state, missing issued client ID and session revocation fail closed. A prior valid connection is retained until a replacement validates.

Do not paste passwords, provider access/refresh tokens, Hermes credentials or API keys. The one-time bootstrap code is a sensitive short-lived authorization capability, not a manual permanent shared-server token. No production credentials were created during implementation.

## Credentials, lifecycle, ownership

Credentials are AES-256-GCM encrypted with owner ID as authenticated associated data, stored atomically with mode `0600` at `<AUTH_PATH directory>/providers/<SHA256(internal user ID)>.enc`. Registration ID, subject, retained ID token, scopes and rotating refresh token stay together. Encryption key is a separate file; startup rejects group/world-readable key files and a key placed directly in provider directory. User/history paths derive from internal authenticated owner IDs, never client input. Legacy unowned history is never shown to account sessions.

Near expiry the server sends the standard refresh grant with the saved issued client ID and API resource; rotating credentials are saved together. Refresh identity, when supplied, must match the stored subject. The minimal runtime **must run one server process/replica**: in-process serialization protects refresh but credential rotation is not coordinated across replicas. Provider work is serialized per owner with context-cancelable waits; unrelated users do not share a network-operation lock. Request bodies are size-bounded, parsed and validated before provider/quota locks are acquired. Cross-process credential locking is still required before scaling. Host attribution/revocation of transferred sessions is documented by OpenAI as not yet available.

Disconnect discovers the trusted OpenAI revocation endpoint and attempts refresh-token revocation, then clears access/refresh/ID tokens locally, retaining only the encrypted registration/subject mapping for later sign-in. HTTP 204 means local credentials were durably cleared and any available refresh token was revoked (or no local credential existed). When revocation cannot be confirmed, HTTP 200 explicitly returns `connected:false, revoked:false` plus `X-Revocation-Status: unconfirmed`: disconnect the app in ChatGPT Settings as well. If the encryption key is not configured, disconnect durably deletes the encrypted record, losing its registration metadata; restoring the key cannot reconnect that owner. Storage failures return non-2xx rather than claiming disconnect. Native UI gives this standing warning. Apple **logout revokes that app session**, cancels its pending bootstrap usability, clears local content/Keychain; it deliberately preserves the user's separately connected provider for another signed-in device. There is no account-deletion endpoint yet.

## Inference and bounds

Every personal translation fetches the same user's current `GET https://api.openai.com/v1/models` catalog; only `visibility:list` entries are eligible. Choose `gpt-6-luna` **only if offered**, otherwise the first visible entry in server order. No invented `gpt-6.1-luna` ID or assumed model entitlement.

Calls use public `/v1/responses`, `store:false`, `stream:true`, with cancellation and no redirect forwarding. Parse SSE deltas and require `response.completed`; failed/incomplete/refused/oversized/interrupted streams are not saved. Errors returned to clients are bounded and do not expose upstream response bodies/tokens. Input: 8000 Unicode characters, 64 KiB JSON; output text: 64 KiB; upstream SSE total: 2 MiB. Translation rate: 20/minute/user, connect: 5/minute/user, provider status/mutations: 30/minute/user. Inbound HTTP headers have a 5-second deadline; the entire request body has a 10-second read deadline, and idle keep-alive connections expire after 60 seconds. There is no response write deadline that would truncate long inference/streaming; upstream HTTP client timeouts remain in effect. History files are owner-only; GET returns newest 100 (disk retention is not yet capped).

## Precise remaining gates

- **No live Apple/ChatGPT consent or real inference was performed.** User must approve ChatGPT plan scopes. No paid call, token reuse, commit, push or deployment happened.
- Updated Release simulator app builds with ad-hoc signing and passes codesign verification; compiled pairing labels exist in de/en/ru/es/fr. English/Russian signed-out launch screens were inspected. Real authenticated iOS approval taps and production device signing remain acceptance gates.
- Production origin HTTPS/DNS availability was not changed or re-verified in this task. It must be operational before remote bootstrap.
- **Direct Apple web login is implemented behind a complete server configuration gate**, with Services ID `de.keinemagie.web` and exact callback `https://keinemagie.tinyserve.org/v1/auth/apple/callback`; see [WEB.md](WEB.md) for Developer registration/grouping, secure key setup and state/nonce/form_post verification. Real Apple consent remains unverified. Browser app approval remains an alternative requiring no Services ID. Its previous local Chromium login/logout evidence used a synthetic native identity, not real Apple/ChatGPT consent. Browser sessions never contain a copied native token. Commercial website ChatGPT OAuth additionally requires selected-partner registration; OSS eligibility is not commercial approval.
- This one-connection-per-Apple-user slice does not yet implement multi-account/workspace picker, protected SSH credential import, account deletion or cross-replica refresh locks.
- ChatGPT Responses permission does not establish speech/transcription permission. These remain unavailable; no paid fallback.

## Verified locally

Go unit/integration tests use explicitly synthetic provider HTTP transports, signed test-only RSA identities and temporary encrypted stores; they cover callback state/replay/session binding, signature/issuer/audience/nonce/scope/subject rejection, refresh rotation, revocation, ownership, model selection and terminal stream handling. These are not live OpenAI test results. Swift core tests validate authenticated provider/translation request contracts. An unsigned iOS simulator build exercises native integration compilation.

## Official references inspected

- https://developers.openai.com/siwc/token-sharing-open-source/sign-in.md
- https://developers.openai.com/siwc/token-sharing-open-source/self-hosted-vms.md
- https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference.md
- https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions.md
- https://developers.openai.com/siwc/website.md
- https://auth.openai.com/.well-known/openid-configuration
- https://developer.apple.com/documentation/signinwithapple/verifying-a-user
