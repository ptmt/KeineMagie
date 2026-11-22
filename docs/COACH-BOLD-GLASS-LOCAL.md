# Coach: bolder semantic color + native Liquid Glass (local)

Isolated worktree: `/Users/tinyserve/Projects/KeineMagie-coach-bold-glass`, branch `candidate/coach-bold-glass`, exact base `6bf13f60252dc76e409342a424abbe99bc29fc98`. Original dirty `/Users/tinyserve/Projects/KeineMagie` and the integration worktree were not edited. Local candidate only: no push, release, Apple upload, production mutation or paid provider call.

## Design and platform verification

Verified installed **Xcode 27.2 (27B52), iOS SDK/Simulator 27.2**, runtime build **24B8117**. The user's iOS 27 description is correct for this machine. `glassEffect(_:in:)` and `GlassEffectContainer` are public APIs introduced in **iOS 26.0**, confirmed both in the installed SDK SwiftUICore interface and Apple's live DocC metadata. The deployment target remains iOS 17; earlier systems get the explicit opaque fallback.

Official Apple sources retrieved November 22, 2026:
- `https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views`
- `https://developer.apple.com/documentation/swiftui/glasseffectcontainer`
- `https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)`
- `https://developer.apple.com/design/human-interface-guidelines/materials`

Apple distinguishes standard translucent materials from Liquid Glass and reserves glass primarily for controls/navigation above content. The regular variant supports readable text over varying content. Our composer now uses **`GlassEffectContainer` + `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26))`**, not a translucent fill relabeled as glass. Native multiline `TextField`, `Menu`, send/Stop controls remain inside one shared surface; no stacked glass-on-glass or custom fake keyboard. Removed the old full-width `.bar` background. Reduce Transparency uses a deliberately opaque adaptive surface and a quiet outline, not an imitation glass effect.

- Correct verdict: saturated green; incorrect: saturated red; user/discussion answers: violet accent matching the app's controls. Opaque white text on these surfaces.
- Literal localized verdict text remains and gains a decorative check/cross symbol. Uncertain, failed, canceled and pending states never acquire an invented green/red verdict. Exercise, instruction and working bubbles stay neutral.
- Same compact native top title, weekly **30pt** strip, contextual target highlighting, exact submitted answers, independent discussion draft, plus-menu routes, Stop/recheck/history/owner fences. No backend, Core model, localization or assessment policy edits.
- Baseline captured from the exact base on the real normal simulator. One representative candidate was built, run, exported and visually reviewed **before** the final matrix. Preview is visibly stronger and the glass edge is genuinely native; visual approval remains the user's, not a claim made from API usage alone.

## Evidence and tests

Original XCTest PNG bytes, per-run summary JSON, and SHA-256 manifests are under `docs/coach-bold-glass-evidence/`. Baseline: `baseline/stable-result.png`; early candidate: `preview/stable-result.png`. Native transport is explicitly synthetic; captures do not prove production inference quality.

Observed RED → GREEN source/palette checks cover saturated readable semantic surfaces, real native glass/fallback wiring, and a noncolor verdict symbol. These structural checks are **not** claimed as native geometry tests. Existing neutral contrast guard now checks only neutral surfaces rather than retaining obsolete hardcoded pastel colors.

Executed non-UI gates:
- Core: 112 XCTest, 5 expected wire-fixture skips, zero failures; 89 Swift Testing pass.
- Real AppModel harness: 124 pass; focused Coach/daily harness: 16 pass.
- Contrast/source contracts: 5 pass; existing compact guards: 2 pass.
- Actual Go→Swift Coach wire fixtures pass (including contextual and old schema handling).

Final **Release UI: 60/60 passed**, zero failures/skips: the same 15 tests on normal light, normal dark, SE light and SE dark, sequentially. Each includes 30pt week geometry/source details, stable pending/correct/incorrect/Stop/error contracts, exact draft/menu route/focus preservation, full 44pt targets, native answer-keyboard geometry, Russian AXXXL composer geometry and reading-order labels, and **actual OS Reduce Transparency on → app rendering → original setting restored**. Parsed xcresult receipts retain one warning per run from unchanged DictationPlayer code, described below.

**80 final original PNG attachments** plus four baseline/early-preview PNGs are retained with verified SHA-256 manifests. Representative light/dark normal/SE verdict, pending, error, menu, keyboard, AXXXL and opaque-fallback images were visually inspected. No material new clipping/overlap was found in that inspected scope. At AXXXL the conversation scrolls behind the floating composer; the editable field and both 44pt controls remain fully above the real keyboard. This is not spoken VoiceOver certification.

Actual screenshot sRGB pixel audit: **16 semantic surface/text samples, minimum white-text contrast 6.819:1**. It checks real opaque fill pixels and white interiors on both verdicts/user bubbles in both device/theme pairs, excluding antialiased edges. The script accepts only ±1 channel quantization around source values (UIKit half rounding differs from Python ties-to-even); contrast is calculated from the observed modal pixels, not assumed source RGB. This does not claim every system-rendered disabled control or legacy error label meets that ratio. Neutral secondary source contrast remains ≥6.88:1 light / ≥8.91:1 dark.

Both approved simulators returned to dark appearance and are confirmed shut down; no clones, created/deleted devices or other task processes were touched.

## Harness issue and limitations

The first Reduce Transparency test did not change the switch: Settings exposes a full-row labeled AX switch, whose center is not the thumb. A second attempt enabled the real setting and rendered the opaque composer, but restoration tapped during the SpringBoard transition. The harness now targets the observed trailing thumb, waits for foreground/transition settling, waits for AX value changes, and restores/read-verifies the initial setting. Recovery of the original disabled state passed before the final matrix. Failed attempts remain in scratch and are not counted as acceptance.

Settings switching also surfaces a `DictationPlayer.swift` main-thread AVAudioSession activation warning in unchanged code; a baseline differential for that warning was not run. Do not call the run warning-free or silently change audio ownership in a presentation task.

No full server/web rerun is represented as new evidence: neither changed. Previous integration coverage remains in `COACH-ACTIVITY-INTEGRATION-LOCAL.md`. **Podcasts full-listening coverage remains unsupported/unknown**, not zero or complete. Physical device performance, spoken VoiceOver and production contextual synonym quality remain unverified. All keyboard evidence is the real native simulator keyboard; no compositing or replacement UI.

## Reproduce

```sh
cd /Users/tinyserve/Projects/KeineMagie-coach-bold-glass
python3 native/ci/test_coach_bold_glass.py
python3 native/ci/test_coach_contrast.py
(cd native && xcodegen generate)
# Check the exclusive simulator slot first. No cloning/creation/deletion.
python3 native/ci/run_coach_bold_ui.py
# Pillow is installed in this isolated scratch venv, not system Python.
/Users/tinyserve/.hermes/cache/scratch/km-bold-venv/bin/python3 native/ci/audit_coach_pixels.py
```

The runner uses only `93E1113F-6736-4CCB-827D-0E2F1C3876EA` and `56A70197-59DE-4410-9E76-25272244E9C8`, sequentially with parallel testing disabled. It restores their original dark appearance and shuts down each borrowed device. Existing result-bundle paths must be archived or changed before rerunning; do not delete someone else's evidence.
