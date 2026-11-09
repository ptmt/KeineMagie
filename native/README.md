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
- App icon is included in the asset catalog.

## Localization

The app ships **German (`de`), English (`en`), Russian (`ru`), Spanish (`es`) and French (`fr`)** and automatically follows the system/app preferred language. German is the development/fallback language. No in-app language override is required. `CFBundleLocalizations` and XcodeGen's development language/regions advertise all five.

SwiftUI/settings/account text and runtime app errors use `App/Localizable.xcstrings` in the main bundle; core session/auth/endpoint/API errors use SwiftPM `Resources/*.lproj/Localizable.strings` via `Bundle.module`. Debug local-network permission text uses localized `InfoPlist.strings`. `ProductIdentity` keeps the stable **Keine Magie** brand and default HTTPS URL separate from translated copy; wire keys, routes and Keychain identifiers are unchanged.

The signed-out screen shows exactly four capability rows (translator, dictation, podcasts + shadowing, coach) and Apple's native sign-in control at the bottom. These are product capability names, not claims that a provider is connected. Errors, progress, cancellation and offline retry/local logout remain conditional. The account screen still reports that ChatGPT is not connected and language functionality is unavailable. The Apple control supplies both its visible title and native accessibility label in the selected system language; no German accessibility override masks it.

Translation source: `ci/localization_data.py`; regenerate resources with `python3 native/ci/generate_localizations.py` and regenerate the Xcode project with `xcodegen generate` inside `native/`. CI checks complete locale/key coverage, format placeholders, bundle configuration and the four-row/native-auth contract:

```sh
python3 -m unittest discover -s native/ci -v
bash native/test-core.sh
```

Verified: **27 Python CI tests and 24 Swift core tests pass**. Release iOS Simulator build with ad-hoc signing succeeds (`CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES`); signature verified and app installed/launched without clearing simulator data or Keychain. Russian and English screenshots captured after `-AppleLanguages '(ru)' -AppleLocale ru_RU` and `-AppleLanguages '(en)' -AppleLocale en_US`. No real Apple/provider authentication is claimed. Existing SwiftPM native-build deprecation and optional AppIntents metadata warnings remain.

## Core tests

```sh
bash native/test-core.sh
```

Verified **24 tests pass**, including five-language package resource and status-formatting coverage. CLT script supplies Testing framework and generated-runner flags. Known SwiftPM native-engine deprecation warning remains; verify actual test count, not build completion alone.

Observed RED→GREEN slices cover exact challenge/exchange wire contract, state rejection, session/logout (including empty 204), signed-out no-network startup, restore/offline/401 policy, real-session persistence, configuration isolation, honest revocation failure, and stale callbacks. Extra regressions cover logout during suspended exchange and revocation-before-clear ordering. Transport and Keychain adapter closures injectable; tests require no live credentials.
