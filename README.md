# Keine Magie

Native iOS app for learning German, with a Go backend. Product specification: [docs/PRODUCT.md](docs/PRODUCT.md).

## Current implementation
- `native/`: SwiftUI Apple identity, Keychain session, personal provider connection, translator/history, account-local style shortcuts, four tabs, and authenticated podcast library with static HTML/audio discovery and manually refreshed RSS/Atom subscriptions.
- Native interface follows German, English, Russian, Spanish or French system/app language.
- `server/`: authenticated translation/history and durable owner-scoped podcast jobs. Recognition runs in an isolated private Linux worker with no provider credentials; translation remains under the owner's backend provider connection.
- `web/`: translator with stable initial layout, named style shortcuts, personal history, direct Apple web sign-in and optional iPhone pairing. Authenticated podcast library supports subscriptions, explicit episode preparation, job actions and timestamped transcripts through the existing owner-scoped API; see [web podcasts and verification limits](docs/WEB-PODCASTS.md). Guest controls fail closed.
- Native and web Coach use saved owner sources and contextual personal `gpt-6.1-terra` assessments, with no fallback. Native translation recovery is durable, compact and GET-only for uncertain receipts. See [coherent Coach publication and limits](docs/COACH-PARITY-PUBLICATION.md).
- Full shadowing remains planned. Share-extension source is opt-in only and **not shipped**: app + extension App Group profiles and signing integration are still required.
- Diktat is implemented on web and iOS: private German texts, whole/guided cached playback, durable drafts/attempts and deterministic checking. Server-only OpenAI Realtime uses `gpt-realtime-2.1-mini` / `marin`, explicit Prepare, no fallback and conservative USD 10/month admission. See [release evidence and limits](docs/DICTATION-RELEASE.md); physical-device listening and Apple processing are separate verification gates.
- Legacy Expo sources remain in Git history.

## Start here
- [Native setup and core tests](native/README.md)
- [Server setup and API](server/README.md)
- [Architecture and privacy boundaries](docs/ARCHITECTURE.md)
- [Xcode and tinyserve deployment](docs/DEPLOYMENT.md)

The native app uses Apple sign-in and a device-Keychain session credential; provider credentials remain on the server. Account identity and connected provider authority are separate. No shared paid fallback is enabled.

## Verification status
Coach web/backend is live from `3498ad73168f11e9d3bf172a5011d62018f939d1`; matching iOS **1.0 (2813.56.44)** was uploaded successfully to Apple on November 22, 2026. The coherent release includes stable semantic chat bubbles, native glass/soft-red styling, meaningful vocabulary clues, aligned web composer, and honest retained weekly activity. **64/64 Release UI**, full Go race/vet, **187 Node pass / 1 skip**, **73 native CI / 1 skip**, Core **113 XCTest / 5 skips + 89 Swift Testing**, and real-Go synthetic browser/wire gates passed. Public HTTPS health/auth denial and **33 exact assets** verified; locked backend-only deployment preserved **56 durable files**, worker/config and the current **10 unsettled speech reservations/$10 cap**. No historical settlement or paid inference was performed. Podcasts listening remains explicitly unsupported; Apple processing/tester availability, physical-device behavior and real-model quality are separate unverified gates. See [exact source, separate server/Apple runs and preservation receipts](docs/COACH-PARITY-PUBLICATION.md).

Historical baseline: the 2026-11-10 release passed Go race/vet, 22 Node 22 web tests, 39 native CI tests (plus 8 executable lifecycle tests), 46 Swift Testing + 3 XCTest tests, a fresh app-only Release simulator build and codesign verification. The isolated Linux fixture recognized real generated German speech; its provider translation was synthetic. Live backend/worker deployment preserved existing account/provider files, returned public health 200 and protected podcast 401, and passed authenticated readiness after worker restart. See [deployment and rollback](docs/DEPLOYMENT.md) for exact artifacts and the manual Compose lifecycle caveat. Real owner-authorized podcast translation and this version's physical-device installation remain unverified; no paid inference was made.
