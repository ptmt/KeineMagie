# Keine Magie

Native iOS app for learning German, with a Go backend. Product specification: [docs/PRODUCT.md](docs/PRODUCT.md).

## Current implementation
- `native/`: SwiftUI Apple identity, Keychain session, personal provider connection, translator/history, account-local style shortcuts, four tabs, and authenticated podcast library with static HTML/audio discovery and manually refreshed RSS/Atom subscriptions.
- Native interface follows German, English, Russian, Spanish or French system/app language.
- `server/`: authenticated translation/history and durable owner-scoped podcast jobs. Recognition runs in an isolated private Linux worker with no provider credentials; translation remains under the owner's backend provider connection.
- `web/`: minimal translator, named style shortcuts, personal history, direct Apple web sign-in and optional iPhone pairing. Authenticated podcast library supports subscriptions, explicit episode preparation, job actions and timestamped transcripts through the existing owner-scoped API; see [web podcasts and verification limits](docs/WEB-PODCASTS.md). Guest controls fail closed. Dictation/coach remain unavailable.
- Dictation, coach and the full shadowing learning loop remain planned. Share-extension source is opt-in only and **not shipped**: app + extension App Group profiles and signing integration are still required.
- Legacy Expo sources remain in Git history.

## Start here
- [Native setup and core tests](native/README.md)
- [Server setup and API](server/README.md)
- [Architecture and privacy boundaries](docs/ARCHITECTURE.md)
- [Xcode and tinyserve deployment](docs/DEPLOYMENT.md)

The native app uses Apple sign-in and a device-Keychain session credential; provider credentials remain on the server. Account identity and connected provider authority are separate. No shared paid fallback is enabled.

## Verification status
The 2026-11-10 release passed Go race/vet, 22 Node 22 web tests, 39 native CI tests (plus 8 executable lifecycle tests), 46 Swift Testing + 3 XCTest tests, a fresh app-only Release simulator build and codesign verification. The isolated Linux fixture recognized real generated German speech; its provider translation was synthetic. Live backend/worker deployment preserved existing account/provider files, returned public health 200 and protected podcast 401, and passed authenticated readiness after worker restart. See [deployment and rollback](docs/DEPLOYMENT.md) for exact artifacts and the manual Compose lifecycle caveat. Real owner-authorized podcast translation and this version's physical-device installation remain unverified; no paid inference was made.
