# Keine Magie — native iOS

SwiftUI, iOS 17+, Swift 6; local `KeineMagieCore`, no third-party dependencies.

## Build

```sh
cd native
xcodegen generate
xcodebuild -project KeineMagie.xcodeproj -scheme KeineMagie -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /Users/tinyserve/.hermes/cache/scratch/KeineMagieAuthDerived CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
```

Simulator build verified with ad-hoc signing. Keep signing enabled for Keychain. `project.yml` preserves team `49PJNAT2WC`, bundle ID `de.keinemagie.app`, and Apple entitlement. Real devices require provisioning with that capability. Simulator ad-hoc code-sign entitlements can be empty even when the project capability is preserved; simulator build success does not prove real Apple credential issuance.

## Authentication

Default **https://keinemagie.tinyserve.org**. Settings contain only server URL, no manual server/OpenAI tokens. HTTPS required except Debug simulator HTTP loopback. Server switching attempts revocation on the old origin before clearing credentials; failures are reported.

Apple-branded native button uses an async coordinator to fetch a fresh challenge BEFORE presenting Apple's sheet:

- Unauthenticated `POST /v1/auth/apple/challenge` JSON `{}` → `{challenge_id,nonce,state}`.
- Native `ASAuthorizationAppleIDProvider` request uses nonce **exactly supplied, without extra hashing**, and supplied state. No name/email scopes.
- Real credential must contain identity token and matching state; invalid state is rejected locally before exchange.
- Unauthenticated `POST /v1/auth/apple` sends only `{challenge_id,identity_token,state}` → `{session_token,user:{id},expires_at}`. No authorization code/email/Apple user ID sent by app. RFC3339 dates support fractional seconds.
- Existing `TokenStore` persists only the session credential in Keychain (`WhenUnlockedThisDeviceOnly`). URL alone in UserDefaults. No credentials logged or redirects followed.
- Startup and foreground restore via Bearer `GET /v1/auth/session` → `{user:{id},expires_at}`. Empty token makes no request; offline retains token but does not display signed-in status. 401/past expiry clears token. Legacy shared token must pass user-session validation and cannot load history.
- Bearer `POST /v1/auth/logout` accepts 204. Revocation attempted **before** local clearing; network/server failure still clears locally with explicit unconfirmed-revocation warning. Keychain failure remains retryable.

Generation guards isolate late challenge/exchange/restore/logout and stale Apple callbacks after cancel/logout/server changes. Session changes clear results/history/input. No active audio player exists at this stage.

## Limitations

- Real Apple consent requires user interaction and correct Apple Developer provisioning. Neither consent nor real end-to-end login has been simulated or declared verified.
- Signed-in UI: **ChatGPT nicht verbunden**. Personal provider connection is planned informational text, not a success-producing button.
- Translation/history/audio unavailable until personal provider integration. UI and app model never invoke legacy translation/history/TTS; no old shared history is loaded. Legacy core tests remain, not enabled features.
- Canceled exchanges may already have created remote sessions. Stale responses are never persisted; such sessions remain subject to server expiry. No failed-logout background retry queue.
- Verify deployment, actual Apple consent, persisted real-session restore, account isolation and physical-device provisioning before declaring end-to-end success.
- No app icon yet.

## Core tests

```sh
bash native/test-core.sh
```

Verified **23 tests pass**, including existing ten. CLT script supplies Testing framework and generated-runner flags. Known SwiftPM native-engine deprecation warning remains; verify actual test count, not build completion alone.

Observed RED→GREEN slices cover exact challenge/exchange wire contract, state rejection, session/logout (including empty 204), signed-out no-network startup, restore/offline/401 policy, real-session persistence, configuration isolation, honest revocation failure, and stale callbacks. Extra regressions cover logout during suspended exchange and revocation-before-clear ordering. Transport and Keychain adapter closures injectable; tests require no live credentials.
