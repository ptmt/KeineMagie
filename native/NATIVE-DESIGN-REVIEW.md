# Native iOS design review

## Scope and changes

Reviewed native SwiftUI separately from the web. Retained NavigationStack, TabView, List, native buttons/sheets, semantic surfaces, existing restrained indigo accent, compact single navigation titles, 112-point scaled editor and small text shortcuts below it. No authentication, server, cache, preparation lifecycle, signing or web changes were made by this native pass.

- Added a localized, noninteractive visual prompt to the empty editor; its existing VoiceOver label remains, without replacing editable accessibility values.
- Removed the second, whole-screen history spinner. History now has one local loading indicator.
- Unknown provider state now shows checking/retry instead of a premature Connect ChatGPT action. Account screen also waits for known status; previously seen provider state remains available during refresh. Account toolbar label is Account, with a neutral person symbol rather than an unverified warning badge.
- Episode detail now identifies the actual episode (API title or URL filename), separates status from transcript, and shows actual API progress only while active. Completed detail has no progress bar. No fabricated summary, vocabulary or CEFR features were added.

## Independent Astra review and limitation

Installed launcher invoked with `--platform ios --repo /Users/tinyserve/Projects/KeineMagie --bundle-id de.keinemagie.app --simulator E3277EBA-C768-4357-ACC0-CFAB3EF88518`, using the already installed/running synthetic fixture. Reviewer did not build or install.

Live catalog advertised exact `openai/gpt-6-astra`, tools, image input and max effort. Audit recorded exact model/max wire requests, no fallback, and provider-returned `openai/gpt-6-astra` labels. These are routing/returned-label evidence, not independent serving-model or reasoning-effort attestation. Image inspection used auxiliary vision.

**Independent review is partial, not complete.** Astra captured the actual Translator using simctl and identified the absent input prompt and unclear shortcut overflow. Native computer-use navigation was blocked. Initial daemon launch-by-name failed; starting the installed CuaDriver bundle by exact path restored daemon setup, but `hermes computer-use doctor` verified Accessibility and Screen Recording permissions are absent. No permission prompts were approved or security settings changed. User grant is required before a full independent native navigation review can run. Launcher `completed:true` only establishes its tool-presence predicate; it does not override this review-scope limitation.

Review/audit log: `/Users/tinyserve/.hermes/cache/scratch/keinemagie-astra-native-review.log`.

## Verification

Xcode 27.2, iOS 27.2. Astra target iPhone 18 Pro UDID above; implementation UI tests used existing booted iPhone 17e `B3D981F2-B0E3-42A3-82E2-1E49CB9B8430`.

- RED: new loading UI test failed for two history indicators, absent provider checking state, premature connection action.
- RED: empty-editor prompt test failed; the final test asserts the localized editor accessibility label, unchanged empty editable value, 44-point shortcut targets at accessibility XXXL, selected state and actual typing. Visual prompt checked from screenshots.
- RED: episode test failed for missing identity and missing active progress.
- GREEN: 13 targeted UI tests passed, 0 failed, including delayed first load, protected-cache restoration/error retention, pending preparation across navigation/foreground, duplicate preparation protection, four tabs, populated podcast bottom safe area, episode ready/active, settings, keyboard layout, custom shortcuts and all five interface languages. A final editor-only rerun passed 2/2 after retaining native editable accessibility values.
- Native CI: 43 Python tests passed, including the executable real AppModel synthetic-transport harness (18 Swift tests).
- Full Core: `xcrun swift test --package-path native/Core --scratch-path /Users/tinyserve/.hermes/cache/scratch/KeineMagieNativeCoreTests` passed 10 XCTest tests and 56 Swift Testing tests. Existing `native/test-core.sh` failed because its CLT/disable-XCTest path cannot import XCTest used by current tests; the full Xcode toolchain alternative passed without modifying the script.
- Release integration: all 5 shortcut UI tests passed, including newly added long German custom title at accessibility XXXL, compact above-keyboard controls and all five locales (`KMShortcutIntegrationFinal.xcresult`). Final native CI ran 43 tests, OK with 1 metadata test skipped because that standalone invocation did not set the built-plist path; executable AppModel harness runs inside this suite. Final Core 10 XCTest + 56 Swift tests passed; ad-hoc signed Release simulator build and `codesign --verify --deep --strict` passed. Duplicate synthetic custom titles retained between test launches caused an initial ambiguous query; regression now uses a unique title and passed the full shortcut suite.
- Final ad-hoc signed Release simulator build passed; distribution signing/upload is a separate GitHub workflow gate, not established by simulator signing.

Evidence: `/Users/tinyserve/.hermes/cache/scratch/KeineMagieNativeVerifiedUI.xcresult`, `/Users/tinyserve/.hermes/cache/scratch/KeineMagieNativeEditorFinal.xcresult`; exported screenshots in `KeineMagieNativeVerifiedUIAttachments` under the same scratch directory. Actual before/after and accessibility screenshots inspected with vision.

## Remaining scope

- Release integration fixed shortcut sizing: native horizontal ScrollView retains intrinsic single-line chip widths without ellipsis/wrapping, shows the platform scroll indicator, and keeps add/manage controls pinned. Accessibility XXXL long German custom-title UI regression verifies content wider than the viewport, scrolling, selection and 44-point targets. A clipped strip edge is the intentional horizontal viewport, not truncated label content.
- Episode detail provides existing timestamped transcript/translation only. Summary/vocabulary/CEFR presentation was not added; native feature parity requires a separate API/data scope.
- Five locales remain managed by iOS app/system language preferences; no custom native language override added.
- Dictation/Coach retain honest unavailable screens, not simulated progress.
- All service data and preparation calls in UI evidence are existing synthetic simulator fixtures. No real Apple sign-in, ChatGPT consent, provider jobs or authenticated production behavior was verified.
- Existing ForegroundUITests actor-isolation warnings and launcher computer-use permissions blocker remain.
