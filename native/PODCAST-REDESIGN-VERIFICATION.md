# Compact tabs and podcast list verification

Based on main `492ef24`. No commit, push, production requests, dependencies, or borrowed artwork.

## Changes

- Single outer NavigationStack preserved. MainTabsView owns inline selected-tab title and podcast + toolbar; RootView keeps settings and only displays product name when signed out. Signed-in Translator/Dictation/Podcasts/Coach have no brand heading or subtitle.
- Podcasts root is a plain native List of subscriptions and imported episodes with localized processing states; feed navigation shows actual API episode metadata. Imported detail retains transcript, translations, retry and cancel. Swipe unsubscribe/cancel/delete remain authenticated.
- Native ContentUnavailableView with concise + guidance. Add URL form moved into a sheet with explicit Episode/Feed selection and language direction; privacy and technical limitations are collapsed. Copy and clean tab labels cover de/en/ru/es/fr.
- API models currently have no artwork fields: no thumbnail URLs or fabricated artwork were added.
- Request handlers guard busy/URL/worker as applicable and reject completion/error state across cancellation, sign-out or session generation changes. Shared inbox still requires a foreground add-sheet confirmation; foreground inbox reload remains.
- Simulator-only synthetic transport exercises actual PodcastAPI decoding and UI (no network/Keychain/provider login). These are fixture screenshots, not real podcast account evidence.
- TranslatorView/TranslationShortcutsView changes were made by the parallel translator agent, not this podcast task. Updated one foreground test to assert its new connect action rather than the removed status subtitle.

## TDD and checks

- New Python podcast contracts first failed for old label/form/nested navigation.
- UI tests caught missing child + toolbar and false worker-unavailable state in a sheet. Toolbar moved to TabView, and sheet explicitly captures capability state; tests passed after fixes.
- `KM_BUILT_APP_PLIST=… python3 -m unittest discover -s native/ci -p 'test_*.py' -v`: **42 tests, passed, no skips**. Includes real AppModel harness with **8 Swift tests**.
- `swift test --package-path native/Core --scratch-path …/km-podcast-core`: **46 Swift Testing + 3 XCTest tests passed**.
- Debug simulator full XCTest: **12 tests passed** (4 foreground, 5 podcast, 3 translator shortcut).
- Podcast UI covers populated subscription/import rows, feed episode navigation, last row above tabbar, empty state, + sheet, invalid URL submit disabled, failed POST visible without losing draft, delayed old-account import through foreground account replacement, five translated add sheets and all compact tab-name headers.
- Release simulator build: **BUILD SUCCEEDED**, ad-hoc signed; `codesign --verify --deep --strict` passed.
- Compiled Release main catalog has correct Podcast/Подкасты values and translated add labels for all five locales; all five Core bundle tables exist (10 compiled tables total).
- `git diff --check`: passed.

## Artifacts

All below `/Users/tinyserve/.hermes/cache/scratch/`:

- `km-podcast-final-ci.log`
- `km-podcast-core.log`, `km-podcast-core/`
- `km-podcast-final-ui.log`, `km-podcast-final-ui.xcresult`
- `km-podcast-release.log`, `km-podcast-release/Build/Products/Release-iphonesimulator/KeineMagie.app`
- `km-podcast-final-attachments/manifest.json`

Final retained screenshots in `km-podcast-final-attachments/`:

| State | File |
| --- | --- |
| Empty | `C77108FB-D4E0-4385-A956-152AEC030D50.png` |
| Populated synthetic | `E3A8209C-E7A8-419D-8BC7-D4F99C93A4CA.png` |
| Add sheet | `9BB9837B-F7AB-4969-87B7-86000DCF74CF.png` |
| Failed import | `36F2E131-D23E-4E22-BAE2-BF38A3752B2B.png` |
| Feed detail | `CBA76099-2E00-44AE-A69A-C4D51F94803D.png` |
| Last row above tabbar | `34D386FF-8050-41D1-A823-8B2849044E87.png` |
| Russian add | `1BECE5C1-BE29-438E-8F13-A38C19DC94E5.png` |
| Russian compact translator | `E2B7E821-D044-4F6C-8E66-A166CFBC836F.png` |

Vision inspected empty/populated layout and final add sheet, failed import, bottom row and Russian translator. Final add has no false worker warning; failed-import message is visible above keyboard; final episode fully clears the floating tabbar. Russian heading is the tab name «Переводчик», not product name, with styles below input.

Nonblocking Apple AppIntents/tooling warnings occurred. Real Apple consent, live feed/audio fetch, Whisper processing, physical devices, distribution signing and optional share-extension Release rebuild were not exercised by this change. Computer-use backend unavailable; XCTest/simctl provided working screenshot/UI verification instead.
