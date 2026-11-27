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

**Local web candidate (not published):** the latest user correction supersedes the inline-month breakpoint. Coach now keeps the 30px week at every width; the compact month is an explicit Activity disclosure in the existing Profile. See [preview, tests and limits](docs/WEB-PROFILE-ACTIVITY-LOCAL.md). The published release recorded below is unchanged.
Web/backend is live from `046099dfa71f8b1880b2fd8b3575ab47c7246efe`: monthly activity at ≥1000px (weekly below), explicit podcast transcript-study activity, starred-source practice, and composer Enter/Cmd/Shift/IME handling. Native **1.0 (2847.89.95)** was uploaded successfully to Apple on **November 26, 2026 at 12:07:32 UTC**, exact source `22791e6fb872e18cbe084883d3d73a920623b5d9`, single UPLOAD run **45813372354**, upload job **139895700895**. Native includes Translator typography matching and request-owned Coach recovery: canceled reads cannot block replacements, stale completion cannot release the new read, and GET-only recovery preserves drafts without unintended entry inference. **56/56 integrated Release UI** on normal/SE × light/dark, **131 AppModel**, **74 native CI (one pre-build skip; actual built-plist checks passed separately)**, **89 Swift Testing + 116 XCTest (six opt-in skips)** passed. Existing web/Go/live-asset receipts and the locked deployment preserving **66 durable files**, worker/config and **10 unsettled speech reservations/$10 cap** are retained. No reconciliation or paid inference was performed; this native follow-up did not redeploy the backend. Apple accepted the upload with SDK warning 90725 (iOS 27 SDK required starting April 2027). Processing/tester availability, physical installation and real-model quality remain unverified; listening is not counted as completion. See [exact source, tests, separate web/Apple receipts and limits](docs/RELEASE-20261126.md).

Historical baseline: the 2026-11-10 release passed Go race/vet, 22 Node 22 web tests, 39 native CI tests (plus 8 executable lifecycle tests), 46 Swift Testing + 3 XCTest tests, a fresh app-only Release simulator build and codesign verification. The isolated Linux fixture recognized real generated German speech; its provider translation was synthetic. Live backend/worker deployment preserved existing account/provider files, returned public health 200 and protected podcast 401, and passed authenticated readiness after worker restart. See [deployment and rollback](docs/DEPLOYMENT.md) for exact artifacts and the manual Compose lifecycle caveat. Real owner-authorized podcast translation and this version's physical-device installation remain unverified; no paid inference was made.
