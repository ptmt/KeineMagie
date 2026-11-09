# Keine Magie

Native iOS app for learning German, with a Go backend. Product specification: [docs/PRODUCT.md](docs/PRODUCT.md).

## Current implementation
- `native/`: SwiftUI Apple sign-in and account/session UI, with four capability rows (translator, dictation, podcasts + shadowing, coach). Personal ChatGPT connection is not implemented; translation/history/audio remain unavailable in the app.
- Native UI/settings/account and session/auth/errors ship in **German, English, Russian, Spanish and French**, automatically following the system/app language (German fallback). Apple’s native sign-in control localizes itself, including accessibility.
- `server/`: authenticated translation/history API and existing cached TTS proxy. Provider credentials remain on the server.
- Podcasts/shadowing and coach tabs are explicitly planned, not implemented.
- The legacy Expo client has been removed; its sources remain available in Git history.

## Start here
- [Native setup and core tests](native/README.md)
- [Server setup and API](server/README.md)
- [Architecture and privacy boundaries](docs/ARCHITECTURE.md)
- [Xcode and tinyserve deployment](docs/DEPLOYMENT.md)

The native app uses Apple sign-in and a device-Keychain session credential; it does not expose manual server/OpenAI tokens. The legacy backend translation endpoints use a server API key and bearer authentication, but are not invoked by the current native account UI. Eligible ChatGPT Pro/Business plans may supply API credits after activation; that is distinct from direct subscription sharing in participating apps. See the product document for official sources.

## Verification status
Native verification: **24 Swift core tests and 27 Python CI tests pass**, including localization completeness/placeholders, four login rows, session/auth policy and signing configuration. XcodeGen generation and a real Release simulator build with ad-hoc signing succeeded; the installed app was launched in Russian and English and screenshots inspected. Existing simulator data and Keychain were not erased. Real Apple consent, physical-device provisioning, personal ChatGPT connection, live provider requests and audio playback are not claimed verified. See [native README](native/README.md) for architecture and limitations. Server verification is outside this native-only change.
