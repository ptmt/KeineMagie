# Coach composer actions — local iOS preview

November 20, 2026. Base `984e34ed7b8d1f840e10a386aa8fe641090d9412`; local-only revision. No push or release.

## Changes

- Replaced the separate contextual chip row with a native SwiftUI `Menu` behind a 44×44pt plus **inside** the composer's leading edge. Send remains trailing. There is no attachment picker, custom sheet, primary action, menu-open request, or menu-open reveal.
- Every server-supplied quick action is included (removed the three-item truncation). Explicit selection retains the original action/text/turn ID and `preserveDraft: true`; reveal retains `source` and does not request follow-to-bottom. Study/assessment/daily admission logic is untouched.
- Menu commands remain disabled while busy or offline. Per Apple's Menus HIG, the menu itself stays discoverable so users can inspect the unavailable commands; an empty menu is disabled.
- Five-language accessible label: Coach actions. The menu uses the concise localized **Progress** label to avoid hyphenation at maximum Dynamic Type, while the existing `My progress` request payload remains unchanged. Hint and all other labels reuse the catalog.
- At accessibility sizes, the native editable TextField occupies a full-width row, with plus and send below it inside the same rounded composer. Text is neither shrunk nor replaced with a painted placeholder. The plus is a fixed-size symbol within a 44pt target, like the existing send symbol.
- No empty 44pt chip row remains. Earlier/active-history/Latest navigation is retained; Latest stays trailing at ordinary sizes. Existing focused-answer ownership and explicit bottom marker are unchanged.
- Composer AX grouping keeps the conversation first, then the native message field and its actions/send. This is an accessibility-tree test, not a spoken VoiceOver claim.

## Platform review and sources

Independently fetched official Apple documentation on November 20, 2026 (DocC JSON when the configured web extractor could not extract pages):

- `https://developer.apple.com/documentation/swiftui/menu` — content/label initializer presents a menu; the separate `primaryAction` initializer performs a tap action. This implementation deliberately uses the former.
- `https://developer.apple.com/design/human-interface-guidelines/menus` — concise labels, meaningful consistent symbols, unavailable commands visibly disabled, menu still discoverable.
- `https://developer.apple.com/design/human-interface-guidelines/materials` — Liquid Glass belongs in the functional/navigation layer; avoid applying it throughout content.
- `https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass` — rebuild with the current SDK and favor standard controls and their native appearance rather than extra custom glass effects.
- `https://developer.apple.com/documentation/swiftui/view/menuorder(_:)` — verified default priority ordering near the interaction point; retained native ordering rather than inventing a bespoke presentation.

Installed environment: Xcode **27.2 (27B52)**, iOS Simulator SDK **27.2**, runtime **27.2 (24B8117)**. The installed arm64 SwiftUI interface exposes the no-primary-action Menu initializer (lines 8992–8996). Review uses actual Release simulator UI, not an ImageRenderer mockup.

Composition: standard NavigationStack/toolbar and tab bar retain their system styling; the transient menu uses system styling; exercise/message content remains neutral and readable rather than glass cards. The primary explicit Check, quiet Skip, separate discussion editor, history navigation and global player remain distinct. No broad redesign was made.

## Verification

**Final-source acceptance is incomplete:** normal/dark `normal-acceptance.xcresult` **33 passed / 0 failed**; small/light `small-final-acceptance.xcresult` **31 passed / 2 failed**. All **30 Coach tests passed on both devices**. The small run passed cross-tab WAV playback, but Stop and back/draft tests failed during their fixture creation, before exercising their assertions. The reused synthetic fixture now contains exactly **30 dictation records**; `server/dictation.go:214–215` rejects a new record with `history limit`. Blocked path: `DictationPlayerUITests.launch()` → `dictation-create` → `POST /v1/learning/dictations` → missing `dictation-prepare`. No history records, limits, or spending ledgers were reset. A new empty fixture was started diagnostically but stopped before any test used it; do not treat that as an accepted bypass. An owner-approved fixture cleanup/isolation decision and a coherent small-device rerun remain required.

Supplementary composer checks: normal/light **2/2**, small/dark **2/2**. Source hashes cover all 207 tracked native files; the same Release build was reused without rebuilding for the small runs. Actual screenshots, transport receipts, attachment maps and summaries are in `docs/evidence/coach-composer-menu/{small-light,small-dark,normal-light,normal-dark}`; machine status is `acceptance.json`. Both borrowed simulators are shut down, and no fixture listener remains. Protected original hashes match: KeineMagie **304/304**, AnyProgress **13/13**.

Pre-final checks: `small-final.xcresult` **33/33** (light), `small-dark.xcresult` **2/2**. The first normal run was **32/33**: the history test tapped an AX-reported hittable Earlier label hidden beneath system navigation (y=40.5–56.2, navigation y=62–116). The new geometry test then failed on the existing 15.7pt Earlier target. Moving its existing 44pt frame inside the button label/content shape fixes the actual target without changing row layout or history logic; the focused RED→GREEN result is **0/1 → 1/1**. Both history tests now require the control below navigation before tapping; archive/page assertions are unchanged. Coherent final suites are rerun on identical final sources on both devices. Working artifacts: `/Users/tinyserve/.hermes/cache/scratch/coach-plus-menu/`.

One subsequent small run passed all **30 Coach tests**, but its three player tests could not connect: the existing fixture exits after an internal 20-minute timer, regardless of a longer `go test -timeout`. The fixture log records a clean exit at 1200 seconds. Restarted the isolated fixture and reran the entire 33-test small suite, without modifying source or weakening assertions.

RED provenance:
- `menu-red.xcresult`: missing composer action control against the unmodified UI.
- `menu-green.xcresult`: 2/2, initial native menu and Russian placeholder.
- `small-coach-first.xcresult`: 27/29. Caught native AX ordering and the obsolete chip-height constraint; actual German maximum-size menu image also exposed avoidable hyphenation.
- `menu-disabled-red.xcresult`: correctly failed when the entire busy/offline menu was disabled instead of keeping disabled commands discoverable.
- `menu-focused-green.xcresult`: 3/5, including corrected single-line native maximum-size menu, every available action, busy/offline behavior. Remaining diagnostic failures were AX order expectation and an edit test's space/delete sequence invoking the native correction popover. The latter was changed to delete/retype a letter without changing production input behavior.

The geometry tests were not relaxed to hittability: full Check/Skip maxY must remain at least 8pt above the **composer container**, both before and after menu dismissal. Native menu height is bounded to one full-size line plus system padding (not the removed chip's fixed 70pt ceiling), with complete on-screen bounds. Five native placeholders are measured using the corresponding accessibility UIFont; the new composer controls retain 44pt targets. Native PNGs are inspected separately.

Swift Core `swift test --filter Coach`: **22 passed, 0 failures**. Server `go test -json -run Coach -count=1 ./...`: **38 passed, 0 failed, 2 skipped** (`TestCoachTwoClientBridge` and `TestCoachWireExport` require their separate opt-in runners).

Opt-in simulator-only transport receipts assert unchanged command journal after open/dismiss and exactly one original `reveal|source|synthetic-coach`, then one `progress|My progress|`. Visibility acknowledgments are excluded from this command journal; the production seen-receipt behavior is unchanged. Both message and exercise editing are exercised across menu dismissal. No live AI is involved.

## Limits

- Simulator evidence, not physical-iPhone, spoken VoiceOver, live backend, or real-provider acceptance. Device theme names describe Coach tests; the existing player suite explicitly chooses its own themes (the `global-coach.png` traversal capture is light; Stop regression loops light and dark).
- Maximum Dynamic Type legitimately scrolls upper exercise content offscreen. The system may temporarily hide the keyboard to fit a large native menu. No claim that the entire lesson, menu and keyboard fit simultaneously.
- Existing unrelated XCTest actor-isolation warnings and DictationPlayer activation runtime warnings remain. No study/player behavior was changed to silence them.
- No user Health data, paid AI/TTS, production mutations or publication. Local global-player checks use the existing generated eight-second WAV and real local Go handler.
- Reuse only the specified normal and small simulators, sequentially, with cloning disabled; shut both down after exporting evidence. Unrelated originals and the parent's AnyProgress copy edit are not modified.
