# Native quiet translator controls — 2026-11-12

Scope: native iOS only. Web, backend, primary Translate, navigation and direction are unchanged.

- Friendly/Formal/custom styles are footnote-sized clickable text without backgrounds, capsules or decorative checkmarks. Selection uses weight/foreground plus the existing accessibility selected trait. Horizontal intrinsic-width single-line scrolling remains; controls retain at least 44-point targets. Add/manage remain quiet compact icons, not text tags.
- Result copy is icon-only at top trailing, a 44×44 invisible target. Existing identifier `translation-copy`, exact unmodified clipboard contents and all five localized accessibility Copy/Copied labels are preserved. Feedback is a checkmark for 1.8 seconds; no visible Copy text.
- Clear is an icon inside the input's upper trailing border with its own 44-point target. The editor reserves a 44-point trailing lane, avoiding text/target overlap. Empty input hides clear; clearing changes only the draft, keeps focus/keyboard, preserves output/history/selected style and makes no request. There was no existing clear action to reuse. Clear is disabled while translation is busy rather than introducing new cancellation/stale-result semantics.

## Executed verification

Strict test-first: icon-only test failed on visible Copy text in all five locales, then passed. Clear test failed on missing button, then passed; portable plain-tag regression failed on bordered style, then passed.

Final targeted simulator suites: 10 UI tests, 0 failures, iPhone 17e / iOS 27.2. Includes five-language real app-side UIPasteboard exact Unicode/multiline/whitespace equality, icon-only accessibility, input clear bounds and reserved typing lane, keyboard/focus retention, completed-result preservation, pending clear disabled, compact keyboard layout, five-language tags and accessibility XXXL intrinsic-width custom shortcut regression. Tests use explicit simulator-only offline transport fixtures, never authenticated production or paid inference.

Native CI: 44 tests passed including effective built app plist, no skips. Swift Core: 10 XCTest plus Swift Testing suite passed (see execution log). Release simulator build succeeded with ad-hoc signing enabled; strict/deep codesign verification passed. Existing toolchain warnings (Swift 6 actor-isolation/deprecations and Xcode debugger-version lookup) remain, not introduced as application failures.

Evidence: scratch `km-quiet-*.log`, `km-quiet-native/Logs/Test/*.xcresult`; actual screenshot attachments exported to `km-quiet-screens*`. Normal long Russian input/result and keyboard screenshots inspected; images are explicitly synthetic fixtures, not claimed provider output. Initial shared fixture account had old test tags; screenshot fixture now uses its own identity.

Localization catalog is maintained in place: the older generator currently lacks existing manually-added catalog keys, so wholesale generation was not retained. No unrelated localization entries were removed.

Release workflow/upload evidence is recorded in `docs/TRANSLATION-COPY.md` after exact-commit readback. App Store processing, TestFlight tester availability and physical iPhone behavior are separate unverified gates.
