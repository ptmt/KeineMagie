# Native foreground/session regression verification

## Root causes and installed-build diagnosis

- The obsolete `AccountView` lived inside `App/KeineMagieApp.swift`. It displayed `Verbinden – in Planung` and the planned-provider paragraph. `585a918` removed those UI references; `f0648ea` replaced the signed-in route with `TranslatorView` and Safari connection navigation.
- Both legacy phrases remain in `App/Localizable.xcstrings` and the localization generator's data. Those entries are resources, not reachable Swift views. Searching the catalog alone does not prove an old screen can render.
- Only the tracked `native/project.yml` generates the application project. Its sources are `App`; the workflow regenerates that project and archives `native/KeineMagie.xcodeproj`, scheme `KeineMagie`, configuration Release. There is no second tracked legacy application entry/project.
- GitHub run `42653211832` at `f0648ea67129f97cbded44d1faaa93c3973eb495` successfully archived/exported/uploaded **1.0 (2702.55.92)** on November 9. Logs explicitly report `UPLOAD SUCCEEDED with no errors`. Run `42605971559` uploaded **1.0 (2700.67.79)**. Earlier `42525424737` uploaded **1.0 (2695.78.58)**, before planned-account removal. No downloadable Actions artifacts exist for the latest run; upload success is not proof of App Store processing, tester selection or installation on a physical phone.
- The screenshot supplied to the parent was not available to this subagent. The quoted old text matches legacy source, but the physical installed version/build remains unknown. Settings now displays the actual bundle version and build for future comparisons.

## Actual latest-source bug and fix

Root's foreground callback called `SessionController.restore()`. That unconditionally incremented generation, cleared user, and switched signedIn to restoring. Root consequently replaced the translator with LoginGate, and its generation/phase observers cleared drafts/history/provider state. This bug existed in the latest Safari build; it was not explained away as merely an old install.

Restore now validates an already-known session silently, preserving phase/user/generation until a definitive invalid response. Concurrent requests coalesce; stale responses after logout/server changes cannot restore an old identity. A real 401 (including decoded expired/invalid identity) clears the identity and invalidates content, even if Keychain deletion fails; transient failure retains an already-validated session and credential, while cold unvalidated restore stays fail-closed. The root validates on return from actual background, not every inactive→active transition (including initial activation/system sheets).

## Reproducible checks

```sh
swift test --package-path native/Core
python3 -m unittest discover -s native/ci -v
xcodegen generate --spec native/project.yml
xcodebuild -project native/KeineMagie.xcodeproj -scheme KeineMagie \
  -configuration Release -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test
```

- Swift executable regression first failed with `.restoring`, nil user and changed generation, then passed after the fix.
- 41 Swift tests; 30 Python contracts; 4 Release simulator XCTest UI tests passed on review rerun.
- Review blockers have independent executable RED→GREEN evidence: A→B validation originally left generation at 1 (expected invalidation), and malformed stored credentials originally retained signedIn/user/generation without attempting deletion (11 failed assertions covering successful/failed deletion). Both focused tests passed after their respective fixes.
- Successful foreground validation preserves content only when the returned user ID matches. A changed identity increments generation even while phase remains signedIn. Existing RootView generation observation invokes `resetSessionContent()` (including cancellation of ChatGPT tasks/loopback/browser); translator `.task(id: generation)` reloads account-scoped data. AppModel history/provider/translation/connection completions check the captured generation before applying their results.
- The additional account-change UI test seeds synthetic account A history/provider, edits a private draft, starts a deliberately delayed translation, then backgrounds/reactivates. Account B remains signed in while the draft/history/provider are reset; the late account A result cannot repopulate the model.
- `AuthError.invalidCredential` now uses the same definitive invalidation path as HTTP 401: user cleared and generation invalidated before Keychain deletion; failed deletion shows a Keychain recovery error, never retains signedIn or labels the credential rejection as a transient network failure. Same-account success/network-transient and HTTP 401 regressions still pass.
- Unsigned generic-iOS Release device compile passed. The resulting iphoneos executable contains none of `KM_SIMULATOR_SESSION_FIXTURE`, fixture user/result markers or `SimulatorSessionFixture` symbols (checked binary bytes and `nm`). No device signing, archive, upload or physical-device execution was performed.
- UI tests exercise real root/AppModel/session navigation with an explicit **simulator-only in-memory synthetic transport**. No Apple login, real session credential, provider connection or external API is simulated as real. Fixture code is excluded from device builds and does not access Keychain or the network.
- Three home→activate cycles with a deliberately delayed validation retain translator/input and no full session loader. A separate synthetic 401 returns to the native sign-in gate. Settings shows `1.0 (1)` for the local simulator build (not a TestFlight build).
- Ad-hoc Release signature verified with codesign. Compiled app and nested Swift package resources contain all five locales. A captured/visually inspected simulator screenshot displays translator/editor/history, ChatGPT disconnected, no planned-account text and no loader.

Real Apple authentication, OpenAI consent, TestFlight processing and the user's physical installed build were not verified. No commit, push or upload was performed.
