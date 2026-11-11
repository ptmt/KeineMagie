# One-tap translation copy

- Web reuses the existing output-header Copy button; completed result only, not source/enrichment or a partial stream. Native adds a borderless `doc.on.doc` Label at the result card's top trailing edge, minimum 44-point target; no selection/scroll interception.
- Exact translation strings go to the clipboard unchanged (including leading/trailing whitespace, multiline Unicode and literal nested JSON). Empty output cannot be copied. Web uses secure-context Clipboard API, then a temporary readonly textarea/`execCommand('copy')`, restoring focus, selection and scroll and removing the temporary private content. Both APIs failing produces an inline error, not a false confirmation.
- Copy/Copied labels are localized in German, English, Russian, Spanish and French. Confirmation resets after 1.8 seconds, with no modal. Identity/reset removes the output/action; never automatically erases the user's system clipboard.

## Verification

Tests were run before implementation and failed on missing visible confirmation/web and missing native copy action. Chromium's real clipboard readback passed **22 checks** with a **64,838-character** synthetic output, modern and actual legacy copy paths, exact Unicode/whitespace/JSON literals, mobile/desktop target reachability, all locales, zero copy-triggered API work, inline denial and owner reset preserving the clipboard. No provider inference or real account data is used.

Native simulator UI test `TranslationCopyUITests/testOneTapCopiesExactCompletedTranslationInAllLocales` passed for all five locales (66.749 seconds). It submits a synthetic transport result, taps the real visible button, verifies the 44-point target, localized transient confirmation and app-side **actual `UIPasteboard.general.string` equality** to the full long fixture. Test runner pasteboards are cross-process; a simulator-only opt-in probe reports equality through the button's accessibility value. Device builds exclude the fixture/readback probe.

Node 61 tests passed; seven browser regression suites (including direction/style/guest) passed. Native CI 43 tests passed with one existing built-plist metadata skip; Swift Core passed. Local execution evidence: scratch `km-copy-*.log`, `km-copy-build/Logs/Test/*.xcresult`.

## Release

Implementation **`9f784f80d97989e0d49369fd6d5e2fd726ce067b`** pushed/read back on main. Public HTTPS health **200**, all **16 public asset bytes** equal source. Actual deployed HTTPS assets also copied a **46,841-character** synthetic result exactly to Chromium's real clipboard; live guest remains disabled. Mobile output-header action inspected unobstructed. API interception was explicitly synthetic, not an authenticated production provider test.

Backend-only image **`e3e1302d9795772baab7d28c19e4e121ba35cffe95b5adaa5afca7f7ba03c31c`** replaced prior `9f73d21b4efe…` via established manual base+override Compose lifecycle. Worker `a61794a3d7e7…` and all unrelated IDs/config/mounts/network preserved. Under store/account locks: idle one completed job, 2113 segments/translations; six nonruntime data files unchanged. Private six-volume backup `deployment/release-copy-20261111T172337Z/` (0700/0600), with prior override for binary rollback without restoring historical data.

Server-image CI [43067573894](https://github.com/ptmt/KeineMagie/actions/runs/43067573894) succeeded. Exact-source iOS [43067573974](https://github.com/ptmt/KeineMagie/actions/runs/43067573974) validation and sign/export/validate/upload succeeded; build **`2720.23.35`**, log **`UPLOAD SUCCEEDED with no errors`**, **2026-11-11T17:29:51Z**, delivery **`fbb9ac26-d92b-486b-b371-c73b0258b2fe`**. App Store processing, tester availability and iPhone installation remain unverified. Native CI built-plist metadata rerun passed 3/3 (resolves the local initial skip).

No paid inference, owner cookies, credential extraction, quota resets or worker replacement. Initial Python urllib public fetch received 403; normal TLS curl and real Chromium verified the live assets instead. Existing Node experimental localStorage warning remains; tests passed. Native keyboard-visible copy and physical-device behavior were not separately exercised.
