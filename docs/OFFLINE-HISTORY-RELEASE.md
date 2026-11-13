# Offline-history publication

## Quiet-history follow-up — 13 November 2026

- Source: **`01d73d785ecae1f37cd0e97fad8f3edc334d2d2a`**, committed/pushed to existing `main` after independent source/security review and real local tests. No substantive review regression found; cache/session logic unchanged.
- History spinner removed entirely; provider checking uses localized quiet text. No false empty while pending; cached rows and errors/retry remain visible. Production transport's eight-second resource limit prevents ordinary stalled first loads from remaining indefinitely blank.
- **Build `2735.19.43`**. Existing automatic [iOS TestFlight run `43412876271`](https://github.com/ptmt/KeineMagie/actions/runs/43412876271) **success**, exact head SHA matches source above.
- [Validate job `131843384092`](https://github.com/ptmt/KeineMagie/actions/runs/43412876271/job/131843384092) and [upload job `131844885213`](https://github.com/ptmt/KeineMagie/actions/runs/43412876271/job/131844885213) **success**; signing cleanup succeeded.
- Apple explicitly reported `VERIFY SUCCEEDED with no errors` at **11:03:27Z**, then **`UPLOAD SUCCEEDED with no errors` at 2026-11-13 11:04:30Z**. Delivery UUID **`7fce0f32-f477-4ff4-a2a6-160dac9f5c26`**. Build number independently matched archive and effective build setting.
- Independent local verification: **29 actual AppModel/PodcastStore, 11 XCTest + 65 Core Swift Testing, 45 native CI cases** (one built-plist case skipped initially, then all three metadata checks passed on the actual Release app), **16 Release simulator UI passed**. Slow/fast/empty, cache restart/error, favorite/delete, foreground, owner/401 and unreachable/blackhole tests use synthetic fixtures only. Screenshots reviewed. Details: [`native/OFFLINE-HISTORY-VERIFICATION.md`](../native/OFFLINE-HISTORY-VERIFICATION.md).
- App Store processing, tester assignment/availability and physical installation **not verified**. No real provider tests, paid inference, web/backend deployment or signing changes. `spikes/` and unrelated Python caches left untouched. Local watch timeout was recovered by following the same run, not dispatching a duplicate.

## Earlier offline-access release

- Native source: `1cef99cc2f812cbe209b129ad026e75ca4767ebf`.
- Exact workflow: [43198915582](https://github.com/ptmt/KeineMagie/actions/runs/43198915582), both `validate` and `testflight` **success**.
- Build: **2726.31.95** (`Archiving build 2726.31.95 with manually validated signing`, effective `CURRENT_PROJECT_VERSION` in upload job).
- Apple output: `VERIFY SUCCEEDED with no errors`, then **`UPLOAD SUCCEEDED with no errors` at 2026-11-12 10:23:35Z**. Delivery UUID `ca07be33-94b6-4159-b5df-27277d04481b`.
- Cleanup job succeeded. App Store processing, tester assignment/availability, and physical iPhone installation are not verified.

Root cause, trusted-device policy, test evidence and migration limitation: [`native/OFFLINE-HISTORY-VERIFICATION.md`](../native/OFFLINE-HISTORY-VERIFICATION.md). Existing installations need one successful online native validation after upgrading before secure local provenance exists. An old token plus cache alone cannot safely identify its owner.

Verified locally: Swift core (61 Swift Testing plus existing XCTest suites), 44 native CI checks (built-plist case separately exercised successfully), actual AppModel harness, 15 targeted Release UI tests plus repeated final offline/foreground subsets. Native URLProtocol unreachable/blackhole tests use UUID-namespaced durable synthetic fixtures without production Keychain, auth credential replay or inference. Exported final Release screenshots were inspected and show saved content, an inline notice and all four tabs. Independent read-only Astra review findings were reproduced with failing tests and fixed, including owner replacement/proof-save failure, logout cleanup failure and mutation 401 invalidation.

No backend or web files were included. Concurrent web changes and `spikes/` were left untouched.
