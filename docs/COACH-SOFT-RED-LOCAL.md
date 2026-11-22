# Coach: restrained incorrect-result bubble (local candidate)

Worktree `/Users/tinyserve/Projects/KeineMagie-coach-soft-red`, branch `candidate/coach-soft-red`, exact base `e542fda2d9be22792227e4c8676fe19d302f8b80`. User request: «цвет красный не очень может бордер просто плюс слабокрасный». Original dirty repository and other candidate worktrees were not edited. No push, publication, paid provider call or production mutation.

## Narrow change

Only the incorrect-result bubble changes: adaptive translucent red fill (8% light / 14% dark), restrained opaque 1pt red inset border, semantic `.primary` text. Existing verdict text/cross remain. Green correct and purple user colors are byte-for-byte unchanged; no typography, spacing, composer/Liquid Glass, weekly strip, localization, routes, assessment or backend changes. The overlay does not consume layout space.

## Actual verification

- Source/palette RED observed against the base: the new softness assertion failed on alpha `[1.0, 1.0]`. GREEN: 4 source/palette tests + 2 existing neutral contrast tests pass. These are structural checks, not native UI evidence.
- **24/24 native Release UI tests pass**, zero failures/skips/runtime warnings in parsed xcresults: 6 tests each on normal light/dark and SE light/dark, serially. Xcode 27.2 (27B52), simulator iOS 27.2 (24B8117).
- The four stable-chat tests exercise incorrect pending→result, correct alternative, Stop and transport error while preserving exact answers, discussion drafts and collapsed history. Added full horizontal/result-text bottom bounds against the composer. Two existing tests cover compact answer/keyboard controls and largest Russian native composer placeholder/controls.
- **40 original XCTest PNG attachments** plus per-run JSON summaries/SHA-256 manifests are in `coach-soft-red-evidence/`; hashes read-verified. Fixtures are explicitly synthetic, not production inference.
- Inspected all four incorrect-result previews, representative normal/SE pending and error states, correct green, SE native keyboard and largest Russian composer. Incorrect result has no clipping or composer overlap; faint fill and red outline remain visible in both themes. Unchanged legacy gray transport-error text is outside the new contrast claim. Largest Russian screenshot is the placeholder state, not a claim of maximum-type keyboard certification.
- Actual sRGB pixels: incorrect text **18.873:1 light / 18.448:1 dark**; border-to-fill **4.952:1 light / 5.319:1 dark** on both devices. The 16 incorrect/correct/user samples have minimum text contrast **7.087:1**. Pixel audit excludes antialiased edges; this is not a physical-display or spoken VoiceOver certification.
- The cold build emitted existing unrelated actor-isolation warnings and an Xcode `SwiftCompile normal x86_64` “exit code 0 but produced no further output” diagnostic; the build/test command nevertheless returned 0 and all selected tests actually ran. No runtime warnings were reported by these four xcresults. No unrelated back-end suites were repeated.
- Only approved devices `93E1113F-6736-4CCB-827D-0E2F1C3876EA` and `56A70197-59DE-4410-9E76-25272244E9C8` were borrowed, after checking both shutdown/no other xcodebuild. No clones. Both appearances restored to their initial dark setting and both devices confirmed shutdown afterward.

## Preview paths (original runtime pixels)

Relative to this repository:
- `docs/coach-soft-red-evidence/normal-light/stable-result.png`
- `docs/coach-soft-red-evidence/normal-dark/stable-result.png`
- `docs/coach-soft-red-evidence/se-light/stable-result.png`
- `docs/coach-soft-red-evidence/se-dark/stable-result.png`

The next acceptance gate is **user preview approval**, not publication. Podcasts full-listening coverage remains unsupported/unknown, unchanged. Production assessment quality and physical-device behavior remain unverified.

## Reproduce

```sh
python3 native/ci/test_coach_bold_glass.py
python3 native/ci/test_coach_contrast.py
(cd native && xcodegen generate)
# Check exclusive simulator availability first; archive/change existing result paths.
python3 native/ci/run_coach_soft_red_ui.py
/Users/tinyserve/.hermes/cache/scratch/km-bold-venv/bin/python3 native/ci/audit_coach_soft_red_pixels.py
```

Result bundles/logs: `/Users/tinyserve/.hermes/cache/scratch/km-soft-red-{normal,se}-{light,dark}.xcresult` / `.log`; simulator app artifact: `km-soft-red-derived/Build/Products/Release-iphonesimulator/KeineMagie.app` in the same scratch directory. Historical bold evidence remains intact; its pixel auditor now reads the exact historical base palette instead of incorrectly applying this candidate's palette to old screenshots.
