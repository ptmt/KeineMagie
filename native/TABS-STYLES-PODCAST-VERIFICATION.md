# Native tabs, styles and podcasts verification

Verified locally on 2026-11-10 with Xcode 27.2, iOS 27.2 iPhone 18 Pro simulator
`E3277EBA-C768-4357-ACC0-CFAB3EF88518`. No commit/push, deployed-server mutation,
real Apple authentication, ChatGPT inference or real audio import was performed.
Other agents' existing server/web changes were not modified by this work.

## Integration fixes

- Four signed-in tabs remain translator, dictation, podcasts and coach. Dictation
  and coach truthfully show unavailable states; podcasts opens the library.
- Tab identity now follows session generation, not just user ID. This destroys
  private podcast draft/library state across every identity epoch, including a
  same-ID account on a different server. Pending library completions also check
  generation before applying results.
- Added five-language podcast status labels (including unknown state), language
  direction labels, episode fallback, time formatting and safe generic errors.
  Server error bodies and arbitrary transport descriptions are no longer rendered
  by the podcast library. User transcripts/URLs are still user content, not UI text.
- Optional share extension now has actual de/en/ru/es/fr resources for placeholders,
  rejection, save failures and close action. System compose actions remain native.
- Translation history models retain optional `instructions` snapshots from POST
  and GET without breaking old history that omits the field. Editing a local style
  cannot rewrite these immutable history snapshots. The native history UI does not
  yet offer historical-style reopening; this verification does not claim it does.
- Replaced import-time assertions and the absolute path in `test_tabs_shortcuts.py`
  with three portable unittest discovery cases.

## Executed checks

All logs and build artifacts are beneath `/Users/tinyserve/.hermes/cache/scratch/`.

| Check | Result | Artifact |
| --- | --- | --- |
| `KM_BUILT_APP_PLIST=… python3 -m unittest discover -s native/ci -p 'test_*.py' -v` | 38 passed, no skips | `km-native-final-python.log` |
| Real AppModel harness included in Python discovery | 8 Swift tests passed | Same Python log |
| `swift test --package-path native/Core --scratch-path …/km-native-final-swift` | 46 Swift Testing + 2 XCTest tests passed | `km-native-final-swift.log` |
| Release simulator app, ad-hoc signed | BUILD SUCCEEDED | `km-native-final-release.log`, `km-native-final-release/` |
| Debug simulator XCTest | 6 UI tests passed | `km-native-final-ui2.log`, `km-native-final-ui2.xcresult` |
| Opt-in `project-share.yml` Release simulator app + embedded extension | BUILD SUCCEEDED | `km-native-final-share.log`, `km-native-final-share/` |
| `codesign --verify --deep --strict` on both Release apps | Passed | Command output |
| Compiled main catalog and SwiftPM resource bundle | All five locales present | Release app bundles |
| Compiled embedded share extension | Five locales, five strings per locale | Share Release app |
| `git diff --check` | Passed | Command output |

Generated the ignored Xcode project from `project.yml` again after the optional
share build, so the default app-only release/signing configuration is restored.
The optional extension remains opt-in until both distribution profiles and CI
extension provisioning are configured; simulator signing is not distribution proof.

## Style, request and privacy coverage

- Store tests verify same-owner persistence, different-owner and different-server
  isolation. Keys use an encoded `(server, owner)` tuple, never a session token.
  Definitions live in local preferences; this is namespace isolation, not encryption.
  Do not put secrets in style text.
- The real AppModel harness creates a 1,000-scalar combining-mark style, selects it,
  translates, and inspects the captured actual APIClient transport request body and
  Authorization header. Success clears selection. Account replacement clears draft,
  result, history, styles and selected instruction; returning to the first owner
  reloads its definition without restoring selection.
- API transport tests verify exactly 1,000 Unicode scalars are sent unchanged in
  `instructions`, original text remains unchanged, no global prompt fields appear,
  and 1,001 scalars fail before transport. GET history has no request body. Tests
  use synthetic transports, not a live provider or production account.
- Core tests cover supplementary-plane and combining-mark bounds, corrupt persisted
  definitions, legacy history, and POST/GET instruction snapshots.
- Existing UI account-change test exercises the actual RootView generation observer:
  old draft/history disappear and a deliberately late old-account translation is
  rejected while the replacement account stays signed in.
- UI style test covers create/select/relaunch (selection not persisted)/edit/delete.
- One UI test relaunches in each of de/en/ru/es/fr, checks translated translator,
  style heading and podcast library UI, and retains screenshots.
- Podcast authentication still uses explicit account bearer requests; importing a
  shared URL requires foreground confirmation. The shared URL inbox itself is
  device-level, not account-specific, and stores no credentials.

## Visual evidence and limits

Exported nine retained attachments to `km-native-final-attachments/` (manifest
included). Inspected Russian podcast and German translator screenshots. Brand
`Keine Magie` is intentionally stable. Scrollable chip clipping at the horizontal
edge is expected; the add button stays outside that scroller and visible. Long
podcast descriptions require scrolling on this simulator; the library existence
assertion is not a complete accessibility-size/layout audit.

The simulator session fixture does not inject podcast credentials, so the library
screenshots deliberately show a localized failed-load/empty state, not populated
podcasts or proof of a worker connection. No Whisper execution, real Apple consent,
real ChatGPT consent, upstream audio fetch, physical device or distribution archive
was verified. AppIntents metadata-extraction warnings are nonblocking because the
app does not depend on AppIntents. Existing ForegroundUITests actor-isolation
warnings appeared in the initial clean Debug build; the new shortcut UI methods
are MainActor-isolated.
