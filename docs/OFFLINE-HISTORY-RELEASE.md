# Offline-history publication

- Native source: `1cef99cc2f812cbe209b129ad026e75ca4767ebf`.
- Exact workflow: [43198915582](https://github.com/ptmt/KeineMagie/actions/runs/43198915582), both `validate` and `testflight` **success**.
- Build: **2726.31.95** (`Archiving build 2726.31.95 with manually validated signing`, effective `CURRENT_PROJECT_VERSION` in upload job).
- Apple output: `VERIFY SUCCEEDED with no errors`, then **`UPLOAD SUCCEEDED with no errors` at 2026-11-12 10:23:35Z**. Delivery UUID `ca07be33-94b6-4159-b5df-27277d04481b`.
- Cleanup job succeeded. App Store processing, tester assignment/availability, and physical iPhone installation are not verified.

Root cause, trusted-device policy, test evidence and migration limitation: [`native/OFFLINE-HISTORY-VERIFICATION.md`](../native/OFFLINE-HISTORY-VERIFICATION.md). Existing installations need one successful online native validation after upgrading before secure local provenance exists. An old token plus cache alone cannot safely identify its owner.

Verified locally: Swift core (61 Swift Testing plus existing XCTest suites), 44 native CI checks (built-plist case separately exercised successfully), actual AppModel harness, 15 targeted Release UI tests plus repeated final offline/foreground subsets. Native URLProtocol unreachable/blackhole tests use UUID-namespaced durable synthetic fixtures without production Keychain, auth credential replay or inference. Exported final Release screenshots were inspected and show saved content, an inline notice and all four tabs. Independent read-only Astra review findings were reproduced with failing tests and fixed, including owner replacement/proof-save failure, logout cleanup failure and mutation 401 invalidation.

No backend or web files were included. Concurrent web changes and `spikes/` were left untouched.
