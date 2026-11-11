# One-tap translation copy

- Web reuses the existing output-header Copy button; completed result only, not source/enrichment or a partial stream. Native adds a borderless `doc.on.doc` Label at the result card's top trailing edge, minimum 44-point target; no selection/scroll interception.
- Exact translation strings go to the clipboard unchanged (including leading/trailing whitespace, multiline Unicode and literal nested JSON). Empty output cannot be copied. Web uses secure-context Clipboard API, then a temporary readonly textarea/`execCommand('copy')`, restoring focus, selection and scroll and removing the temporary private content. Both APIs failing produces an inline error, not a false confirmation.
- Copy/Copied labels are localized in German, English, Russian, Spanish and French. Confirmation resets after 1.8 seconds, with no modal. Identity/reset removes the output/action; never automatically erases the user's system clipboard.

## Verification

Tests were run before implementation and failed on missing visible confirmation/web and missing native copy action. Chromium's real clipboard readback passed **22 checks** with a **64,838-character** synthetic output, modern and actual legacy copy paths, exact Unicode/whitespace/JSON literals, mobile/desktop target reachability, all locales, zero copy-triggered API work, inline denial and owner reset preserving the clipboard. No provider inference or real account data is used.

Native simulator UI test `TranslationCopyUITests/testOneTapCopiesExactCompletedTranslationInAllLocales` passed for all five locales (66.749 seconds). It submits a synthetic transport result, taps the real visible button, verifies the 44-point target, localized transient confirmation and app-side **actual `UIPasteboard.general.string` equality** to the full long fixture. Test runner pasteboards are cross-process; a simulator-only opt-in probe reports equality through the button's accessibility value. Device builds exclude the fixture/readback probe.

Node 61 tests passed; seven browser regression suites (including direction/style/guest) passed. Native CI 43 tests passed with one existing built-plist metadata skip; Swift Core passed. Local execution evidence: scratch `km-copy-*.log`, `km-copy-build/Logs/Test/*.xcresult`.

Deployment/remote TestFlight status is recorded separately after exact-commit verification; implementation and simulator tests alone do not establish upload, processing or installation.
