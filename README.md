# Keine Magie

Native iOS app for learning German, with a Go backend. Product specification: [docs/PRODUCT.md](docs/PRODUCT.md).

## Current implementation
- `native/`: SwiftUI four-tab client, German ↔ Russian translation with idioms/patterns/vocabulary and server history; pasted-text listening dictation using OpenAI TTS.
- `server/`: authenticated translation/history API and existing cached TTS proxy. Provider credentials remain on the server.
- Podcasts/shadowing and coach tabs are explicitly planned, not implemented.
- The legacy Expo client has been removed; its sources remain available in Git history.

## Start here
- [Native setup and core tests](native/README.md)
- [Server setup and API](server/README.md)
- [Architecture and privacy boundaries](docs/ARCHITECTURE.md)
- [Xcode and tinyserve deployment](docs/DEPLOYMENT.md)

The private first version uses a server API key and a client bearer token. Eligible ChatGPT Pro/Business plans may supply API credits after activation; that is distinct from direct subscription sharing in participating apps. See the product document for official sources.

## Verification status
Go race tests and vet pass; Swift core has ten passing tests, including history concurrency regressions. XcodeGen generates the project. Xcode 27.2 simulator build succeeded, and the app was installed and launched on iPhone 18 Pro (iOS 27.2). Light/dark translator screenshots were captured. Use ad-hoc signing for simulator runs: disabling signing caused Keychain error -34018; an ad-hoc signed rebuild correctly reaches the missing-server-token state. Live OpenAI requests, audio playback and tinyserve deployment are not verified. Independent code review passed after fixing a history refresh race. This is an initial implementation, not a finished four-feature release.
