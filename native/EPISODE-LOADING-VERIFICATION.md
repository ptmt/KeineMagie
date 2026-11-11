# Native cache, state and idempotency acceptance

## Result: PASS (native scope; no live integration claim)

- Central owner-scoped `PodcastStore` owns preparation Tasks by typed feed/episode key. Synchronous insertion coalesces double taps and calls from different view lifetimes. Navigation/caller cancellation does not cancel the owned Task. Store epoch and session generation reject late completions; reset cancels and removes pending/error state.
- History favorite/delete acknowledgements and new translations immediately persist reconciled history. History rows remain busy through persistence. Cache snapshots carry monotonic revisions; the actor rejects stale revisions. A synchronous invalidatable lease lock spans validation and atomic file write, closing the pre-await generation-check race. New leases fence old writes and queued cleanup. Session reset clears old owner cache; ordinary app termination retains it for relaunch.
- Files are server/owner/dataset SHA256-scoped, atomic, excluded from backup, directory 0700/file 0600, iOS protected until first authentication. Credentials never enter cache. Simulator persistence uses explicit UUID test namespaces, not production cache or Keychain.
- Warm cache is loaded before network refresh. Populated content stays visible during delayed GETs and errors. Podcast endpoints apply independent successful results; failed endpoints retain cached datasets and visible error phase (not verified-empty).
- POST contract remains `url`, `source_language`, optional `feed_id`/`episode_id`. Optional episode `preparation` and job association fields remain backward compatible. Explicit identity wins over legacy URL association.
- Podcast root has only the Podcasts navigation title and rows; Subscribed podcasts section heading removed, localization key retained.
- Fresh translator defaults ru→de. Explicit direction remains unchanged during foreground refresh and existing session reset semantics (direction was not previously reset).

## Executed verification

- Python native CI: 43 discovered, 42 passed, 1 intentional signing-environment skip. Includes actual AppModel Swift harness: **18 tests passed**. Log `/Users/tinyserve/.hermes/cache/scratch/km-native-ci-final.log`.
- Full Core Swift run: **10 XCTest + 56 Swift Testing passed**, zero failures. `swift test --package-path native/Core`; log `/Users/tinyserve/.hermes/cache/scratch/km-core-final.log`. The CLT `test-core.sh` disables XCTest, so full SwiftPM was used to include new XCTest cache cases.
- Full final simulator UI suite: **21 passed, 0 failed/skipped**, iPhone 17e / iOS 27.2. `/Users/tinyserve/.hermes/cache/scratch/KMNativeFinal.xcresult`. Earlier 19-test full iPhone 18 Pro run and 4-test cache suite also passed.
- New/extended acceptance: actual doubleTap, delayed accept/back/reenter pending UI, home/activate accepted association, backend transport POST count exactly one, refresh endpoint-pair count exactly two across concurrent callers, stale uncancellable completion rejection, failure retry, partial endpoint failure, terminate/relaunch cache before delayed/error server, favorite/delete cache relaunch parity, fresh ru→de and explicit-choice foreground preservation.
- Release simulator build and `codesign --verify --deep --strict` passed. Final Debug simulator build passed after UUID namespace validation hardening. Only optional AppIntents metadata warning in Release.
- Screenshots exported to `/Users/tinyserve/.hermes/cache/scratch/km-native-final-screenshots/`. Visually inspected pending-after-navigation, cache-retained-with-error (no Subscribed podcasts header), and ru→de selected screenshots.
- `git diff --check` passed; self-reviewed task lifetimes, stale generations, cache ordering/cleanup, protected mutation snapshots and partial errors. No independent review/integration inference.

## Boundaries

All transport/UI content in acceptance is explicitly synthetic. No live authenticated server, real Apple/ChatGPT consent, remote worker, physical-device data protection or TestFlight acceptance exercised. Scene polling starts only while active; actual request coalescing is tested with suspended endpoint transports, and home/activate UI proves navigation/pending continuity. Cache I/O failures remain best-effort (`try?`), not user-visible durability guarantees under disk failure.

Native files only were edited by this worker. Existing/concurrent server changes were left untouched. No commit, push or deployment.
