# Immediate Translate feedback — local candidate

Base: fresh origin/main `0b7b7804fbcdc12493c6c7f575e990152b2f549a`, source `16709e7e6bc99e9f59dfcb6cfdd90e5c73c6dfb0`.
Isolated branch/worktree: `feat/translate-immediate-feedback`, `/Users/tinyserve/Projects/KeineMagie-translate-feedback`.
No push/deploy, production calls, private credentials or TTS. Original dirty checkout untouched.

## Behavior
- Existing button immediately changes to localized Translating with progress glyph; no extra delayed button.
- Web sets pending class/disabled/busy synchronously before POST. Skeleton overlays the existing output area only when empty; a subtle shimmer overlays retained text. Copy/edit are disabled during the operation. Cancel/success/failure/401 clear pending.
- Native button calls synchronous `beginTranslation`, publishing acceptance before the Task/disk path. Captures source/direction/style and owner generation. Same accepted tap coalesces; another draft may enqueue during transport. Durable save still precedes POST; failed save never sends. Native output footprint is reserved initially to prevent a new pending row shifting history; existing output remains visible, Copy disabled during pending. Keyboard stays open.
- Offline/backoff queued items stop active feedback and retain existing Saved · waiting toolbar disclosure. No provider preflight gate was added. Request identities/owner fences are unchanged.
- Reduced motion uses static bars/glyph; decorative skeletons are hidden from accessibility. Native announces pending at transition; web retains the existing polite status region. Five existing locale strings reused.

## Executed
- RED web first-frame browser assertion failed with `{disabled:true,busy:null,pending:false}` before implementation.
- Web `node --test web/tests/*.test.mjs`: 104 passed.
- `web/tests/translate_pending_browser.py`: 10 locale/viewport scenarios passed. Literal first requestAnimationFrame while synthetic POST held; duplicate exactly one POST; success/502/401/cancel; old full Unicode result retained; Copy disabled; button width/height/x and history document Y stable; desktop light animated and mobile dark reduced-motion CSS animation checks; no horizontal overflow.
- `web/tests/translation_response_browser.py`: 76 checks passed, including accepted-result recovery and safe diagnostics.
- Actual AppModel lifecycle harness: 79 Swift tests passed, including synchronous acceptance before transport, duplicate tap, real disk failure no POST, queue-stop, new snapshot during held request, old result retained and reset ignoring late completion. Existing Coach/Diktat suites included.
- Native Core: 68 Swift tests passed.
- Native CI Python discovery: 53 tests, OK (1 skipped), includes actual AppModel harness.
- Server `go test ./...`: passed (`diktat/server`, 66.398s).
- Release simulator build: succeeded after final accessibility string fix.
- Release native UITest final bundle: 3 tests passed in 254.891s: five-locale pending button/output geometry with keyboard; five-locale provider settlement/navigation no-jump; quiet outbox restore no-jump. Earlier combined run also passed cached-history error five-locale geometry and provider-error geometry before its overall invocation timed out; that interrupted bundle is NOT a completed successful run.
- `git diff --check`: clean. Added-line credential/injection static scan: no matches. No independent review claimed.

## Evidence
- `artifacts/translate-feedback-web/`: ten real browser pending PNGs and checks.json.
- `artifacts/translate-feedback-ios-final/`: final successful xcresult exported screenshots/trees/manifest, including five-locale dark pending.
- `artifacts/translate-feedback-ios/`: earlier diagnostic run, pending screenshots and actual MP4 screen recording (run had a post-success offscreen Copy lookup failure, corrected by scrolling in the test).
- Final xcresult: `/Users/tinyserve/.hermes/cache/scratch/km-translate-feedback-final.xcresult`.
- Logs: `/Users/tinyserve/.hermes/cache/scratch/translate-{ios-final,native-ci-final,native-final,web-final,go,core}.log`.
- Inspected real web desktop/mobile dark and native light/dark images with vision. No visible collisions; with keyboard open native lower output card can be partly below keyboard, scroll remains available. No screenshots were painted/composited.

## Explicit review gaps
- Native synchronous pending state before disk is proven; `Task.yield()` is not a guaranteed compositor-frame barrier before synchronous filesystem access. Simulator captures prove real pending UI during held transport, NOT literal pre-disk first painted frame. A controlled disk suspension seam/compositor probe is still needed for that strongest assertion.
- Native Reduce Motion implementation is present but no dedicated real accessibility Reduce Motion UITest was executed. VoiceOver announcement behavior not listened to with VoiceOver enabled.
- Final tiny `Text(verbatim:)` accessibility catalog compliance change was Release-built and Python-tested after the successful full native UI run; it did not receive another full native UI run.
- No independent reviewer available in this subagent; parent review remains mandatory. No release authorization implied.
