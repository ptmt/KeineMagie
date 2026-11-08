# Authentication decision: Apple identity + connected ChatGPT

## Deployment origin
Chosen backend origin: `https://keinemagie.tinyserve.org`. DNS currently does not resolve. tinyserve daemon responds, but reports degraded state: Traefik and tunnel not running. No DNS record or service has been created for this origin yet. Configure and verify HTTPS before registering concrete server callbacks; callback paths must follow the chosen supported provider flow, not guessed paths.

## Agreed direction
Do not onboard users using a manually entered shared server token. Replace that initial implementation with Sign in with Apple for app identity and a separate, explicitly authorized ChatGPT connection for eligible AI workloads. This is the target architecture, not implemented authentication.

## Apple
Use native AuthenticationServices Sign in with Apple. Server issues a short-lived, single-use nonce challenge; validate Apple's signed ID token against trusted Apple keys, issuer, configured audience, expiry and nonce. Exchange authorization code as required. Use the stable issuer/subject identity, not email, to identify the user. Never link accounts based only on matching email.

Server stores internal user ID, Apple subject, minimal profile, hashed application session credentials and encrypted provider refresh tokens where needed. Passwords and Apple account credentials are never collected. The iOS client still holds its own app session in Keychain; 'server-side storage' does not eliminate the client session credential. Logout/revocation/deletion must invalidate sessions and disconnect providers.

Requires an Apple Developer team, correct bundle ID, enabled Sign in with Apple capability, and server-side Apple configuration/signing credentials for the code exchange. Private signing keys stay outside Git and chat.

## ChatGPT connection
Connect only from an authenticated app session. Bind state, nonce and PKCE to that session and use one-time expiring challenges. Verify provider identity and actual granted Responses scopes before marking a connection usable. Encrypt refresh credentials at rest with an encryption key stored separately from the database, redact tokens from logs and define refresh/revocation/disconnect behavior. Isolate history and provider access by internal user ID.

Official documentation now provides dynamic registration for open-source/local tools and supports a self-hosted host model. Do not substitute Codex credentials or scrape browser sessions. Determine the supported mobile-to-self-hosted callback and credential transfer flow from the official guides before implementing it. Commercial remotely hosted distribution may require partner approval; do not assume personal self-hosted eligibility establishes a commercial deployment right.

Inference uses the public Responses API, not ChatGPT backend-api or the current Chat Completions adapter. Discover account-specific models. Requests require store=false and stream=true; persist a translation only after response.completed, never on partial text or failed/incomplete streams.

The documented subscription grant covers eligible Responses requests. It does NOT establish audio/speech or transcription permission. Treat TTS/transcription as separate capabilities until verified; do not silently use a paid API key as fallback. Show an honest not-connected/not-supported status.

## Next acceptance gates
1. Confirm Apple Developer team and signing capability, final bundle ID, self-hosted HTTPS origin and callback design.
2. Verify applicable OpenAI self-hosted connection flow and audio limitations.
3. Implement tests-first: identity verification, challenge replay rejection, sessions, per-user data isolation, encrypted connections and lifecycle.
4. Replace shared-token settings with Apple sign-in and connected-account UI; no fake connected state.
5. Exercise both real consent flows and a completed translation, then evaluate speech/transcription separately.

## Sources
- https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api
- https://developer.apple.com/documentation/signinwithapple/verifying-a-user
- https://developers.openai.com/siwc/quickstart
- https://developers.openai.com/siwc/token-sharing-open-source
- https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- https://developers.openai.com/siwc/token-sharing-open-source/self-hosted-vms
- https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
