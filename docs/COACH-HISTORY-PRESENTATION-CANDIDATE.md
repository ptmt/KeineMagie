# Coach history/status/scroll — local candidate

Base: origin/main `481bb1c`, including `b3ab6c8b14c5827aef9d903b3a3eb90be51157e8`. Isolated worktree `/Users/tinyserve/Projects/KeineMagie-coach-history`, branch `candidate/coach-history-status`. No push, deployment or Apple upload. Original dirty checkout is untouched.

## Semantics (web and iOS)

- Presentation only. The default view includes complete turn groups whose latest valid timestamp among turn `at`, attempt `at`, and attempt `reviewed_at` is at least opening-time minus 86,400 seconds. Exact boundary included; timezone offsets and DST do not change the interval. Window is captured on entering Coach, avoiding disappearing exercises during a draft. Re-enter/reload recomputes it.
- A single quiet Earlier control exposes/collapses all older groups already present in the authorized snapshot. No delete, pagination mutation, reset, evidence change, assistance inference or mastery inference. An old pending/unanswered exercise has **no active exception** and is available in Earlier. Recent feedback/attempt keeps its entire original exercise group visible. Missing/invalid legacy dates remain visible; future dates remain visible rather than dropping data.
- Completed learner attempts, including wrong/uncertain, are neutral gray and remain fully legible/interactable. Existing older-answer spoiler/reveal rules remain. Skipped exercises use calm muted red and Unanswered; ready exercises use calm muted red and Awaiting answer. Pending assessments use a neutral working accent and Checking, never an incorrect/failed claim. Verdict and explanation remain separate readable text.
- Coach source/hint disclosure, citation links and reveal quick chips are removed from both clients. Source IDs/quotes and server context/evidence stay intact. Natural-language questions still use the existing chat/backend context; this candidate does not add or guarantee a new source-retrieval capability.
- Initial entry/load scrolls to actual bottom. Own message/quick reply explicitly follows; ordinary arrivals/layout changes follow only while following latest. Reading earlier shows Latest rather than forcing a jump; typing a draft alone does not follow. No smooth scrolling/bounce is introduced. Existing viewport receipt gates remain; there is no blanket mark-read or unread reset and no model call added on opening (existing free entry admission remains).
- Web measures message rows and viewport through ResizeObserver. Native uses explicit bottom anchoring, full stack geometry and a bottom sentinel; the previous lazy estimated layout failed the long-history Release test and was replaced with a VStack.

## Verified locally

- RED/GREEN: new JS presentation module absent before tests; Swift presentation members absent before tests; real public asset handler returned 404 before allowlist fix.
- `node --test web/tests/*.test.mjs`: 110 passed.
- `swift test` in native/Core: XCTest 54 executed, 1 existing Go-wire fixture skipped, zero failures; Swift Testing 72 passed.
- `go test -run 'TestPublicWebAssetsOnly|TestCoach' ./...`: passed. New module included in public allowlist and Docker COPY.
- `python3 native/ci/test_coach_compact.py`: 2 passed, including all five new native localizations.
- Real Chromium production DOM with synthetic loopback HTTP: `web/tests/coach_presentation_browser.py` passes all five locales, long history, old-group disclosure/reload, gray correct+wrong, absent source UI, initial/own-send bottom, reading/draft retention through incoming refresh, viewport resize and delayed row height. Existing coach chat/actions browser scripts also pass after updating superseded source/initial-position expectations.
- Release simulator `C7D5A3D2-CD63-46FC-B7A4-A8AB6CE82AEF` (new isolated KeineMagie history candidate): 5 selected UITests passed: two presentation tests (including five locales at accessibility XXXL in actual simulator dark mode), source absence, contextual progress draft preservation and asynchronous pending/correction.
- `git diff --check`: clean.

## Evidence

Latest native run: `/Users/tinyserve/.hermes/cache/scratch/coach-history-ui6.xcresult`.
Export manifest: `/Users/tinyserve/.hermes/cache/scratch/coach-history-release-evidence/manifest.json`.
- Native normal dark initial/status: `C5FD87AD-088E-4796-B8BF-4646C61A6A4F.png`
- Native Earlier: `C66ACAAA-229F-40AA-B9C4-05DFB514607F.png`
- Native own send: `4BBEB5FB-9024-4B85-BAB9-49C7D3FCE076.png`
- Native maximum Russian dark: `9B15F1F3-6CB0-41F1-BB37-20DEF8DC23CD.png`
- Native checking: `52F5A090-869E-44CB-99A8-2EA89F94309A.png`
Web screenshots: `/var/folders/t0/l_p2xys924lbstg8jzlq61vr0000gn/T/coach-history-evidence/web-{en,de,ru,es,fr}-dark.png` (synthetic).

## Limits / parent review gates

- All UI evidence is synthetic, no paid AI/TTS or private user content. No pedagogical/provider accuracy claim.
- Parent visual review and release authorization remain required. Real mobile Safari keyboard, hardware keyboard, VoiceOver traversal, quantitative WCAG color sampling and live authenticated owner data were not exercised. Browser resize simulates keyboard viewport changes, not a physical phone keyboard.
- Native largest-type composer placeholder truncates (existing field behavior); answer controls remain reachable. Long content intentionally scrolls above the visible bottom. Full VStack prioritizes exact geometry but should be profiled against extremely large revealed histories; Earlier is local disclosure, not server pagination.
- Latest activity uses available persisted timestamps; there is no distinct server assessment-completion timestamp in the client contract. Turn completion alone does not manufacture a new timestamp.
- Full legacy UI suite was not run; selected updated/current Coach flows are verified. Legacy source and old initial-top expectations were updated, not preserved as contradictory requirements.
