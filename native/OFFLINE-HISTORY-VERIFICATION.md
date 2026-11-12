# Native offline saved history

## Cause and policy

Cold launch previously persisted only the bearer token. `SessionController.restore()` entered `.restoring` without an owner until `/v1/auth/session` completed; RootView rendered the four-feature login screen, so MainTabsView never ran owner-scoped cache hydration. A blackholed request therefore hid already-saved history. Foreground validation already retained an in-memory owner, but that identity did not survive termination.

Native now records the last server-verified user, exact server origin, token SHA-256 binding and verification time in a separate `WhenUnlockedThisDeviceOnly` Keychain item. Only matching provenance unlocks local read-only tabs immediately. It is not a JWT decode, cache-file owner discovery, browser identity or server authentication bypass. Existing installs require one successful online verification on this version to establish provenance. Expired credentials may still read the securely bound previous owner's local content while validation cannot reach the server; a real 401 invalidates identity and removes provenance. First launch, unknown owner, changed token/origin and malformed credentials remain closed.

Server writes, inference, preparation, favorites/deletion and provider operations require successful online session validation and are disabled while checking/offline. Nothing is queued. Copying displayed history/results stays local. Only actual URL errors produce the localized nonmodal “Offline. Showing saved history” notice; radio labels/NWPath do not prove internet access. Session network requests have eight-second request/resource limits, without waitsForConnectivity. Retry is explicit and does not launch AI.

Cache hydration captures generation/server/owner before awaits. Existing hashed filenames, file protection, owner-only permissions, revision/session write leases and invalidation remain. Hydration runs once per generation so foreground checks cannot overwrite current content with an older disk snapshot. Logout/401 erase secure provenance before slow revocation, and a deny-only preferences tombstone blocks reusing it if Keychain deletion fails; preferences can deny, never grant, offline access.

## Verification (synthetic, no real account replay or inference)

- Core: 61 Swift Testing cases plus existing XCTest cache/shortcut tests passed using Xcode SwiftPM.
- Independent Astra source review found owner-change/proof-write and logout deletion failure edge cases; failing regression tests reproduced both, then passed after fail-closed transitions and best-effort remaining cleanup. Follow-up found mutation-401 provenance retention; an actual AppModel failing test reproduced it and now passes with immediate invalidation/content reset.
- Native CI: 44 Python tests passed, one built-plist check skipped outside a built-app invocation; includes the actual AppModel/PodcastStore harness and durable cache restart with suspended identity verification.
- Release simulator: 15 targeted history/dataset/foreground/offline UI tests passed; unreachable and URLProtocol blackhole relaunch tests also rerun separately after banner placement changes. UUID namespaces keep fixture content/provenance away from production Keychain/cache. Both assert local rows before waiting for validation, offline write disablement, copy, all four tab navigation and selected Podcasts retention after foreground.
- Screenshots exported from xcresult and inspected. Early top/bottom TabView safe-area banner variants clipped content or hid the floating tab bar; final notice is a normal dataset list row, not a root overlay/inset.
- Physical iPhone/elevator connectivity, real Apple/OpenAI authentication, offline audio playback, and TestFlight processing/tester visibility are not established by synthetic tests.

Evidence is under `/Users/tinyserve/.hermes/cache/scratch/km-offline-*`; scratch is temporary. Publication details are recorded after the exact workflow completes.
