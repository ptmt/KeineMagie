# Immediate Translate feedback — independent completion

Candidate reviewed: `c16924e91c7798d9fc1e9bb41b5fe0955df9e26f`, based on freshly fetched origin `0b7b7804fbcdc12493c6c7f575e990152b2f549a`. Original dirty Diktat checkout untouched.

## Review and fix

The original native acceptance published pending synchronously but still encoded and atomically wrote the entire outbox on MainActor after `Task.yield`. That is not a compositor guarantee. Actual AppModel RED test observed a real main-thread journal call. Writes now capture immutable snapshots/revisions synchronously, encode/write in detached work, and await durable success before POST. A revocable owner lease holds one lock across validation and atomic replacement; stale revisions cannot replace newer snapshots, and logout invalidates before purge. Completion rechecks owner/generation/epoch after every new persistence suspension. Automatic queue draining cannot bypass an acceptance waiting for persistence (a first Release failure fixture caught this actual race; fixed rather than weakening its assertion).

Typing changes memory immediately and schedules protected persistence off-main; unawaited typing has the normal process-termination window. Explicit submissions and sending/completion transitions await durable persistence. Initial scope hydration remains synchronous and separate from accepted-tap writes. No arbitrary rendering delay/frame guarantee was introduced.

Old output stays readable; Copy is intentionally disabled while pending. New draft snapshots may queue during held transport. Offline/backoff clears active feedback. No transport/preflight/provider fallback added; storage failure sends nothing. Existing owner, expected-owner and request-ID contracts remain.

## Executed gates

- RED actual-model `translationJournalRunsOffMain` failed on main-thread disk; GREEN full actual AppModel harness **81** including Coach/Diktat, suspended journal/responsive new input, background drain exclusion, logout-no-resurrection, storage failure/no POST, duplicate coalescing, old-result retention and request counts.
- **104 Node**, **10 real browser first-frame locale/viewport cases**, **76 response/recovery browser checks**, Go suite passed.
- Native Python CI **53**, one built-metadata skip; Swift Testing **69** plus existing XCTest suite passed.
- Fresh Release simulator **3 UI tests passed**: actual eight-second blocking journal with responsive input and rendered pending, real storage-failure clears feedback, five-locale dark keyboard/output geometry. Final AX strings were exercised. Actual system Reduce Motion enabled via dedicated simulator preferences/reboot: runtime reports `reduce=true system=true`; actual static hourglass branch and hidden decorative output are present. No VoiceOver spoken-output claim.
- Separate Release animated-path real recording with parallel simulator cloning disabled: **1 test passed**; runtime `reduce=false system=false`, store `main=false`, write held **8.010s**; rendered pending plus typed `Snapshot responsive` verified **1.409s** after tap. Full real MP4 `scratch/translate-review-delayed-store-final.mp4`, inspected extracted frame at 25s. No composited UI. First recording accidentally captured the non-cloned home screen; rejected and rerun on the exact device with `-parallel-testing-enabled NO`.

Evidence under `/Users/tinyserve/.hermes/cache/scratch/`: `km-translate-review-ui2.xcresult` (3 green, actual reduced-motion), `km-translate-review-ui4.xcresult` (animated video test), `translate-review-ui2-attachments/`, `translate-review-diagnostics{,4}/`, final MP4 and `translate-review-{red,green,ci-final,node,core,go}.log`. Candidate web evidence refreshed in untracked `artifacts/translate-feedback-web/`.

## Delivery

Pending source push, backend exact-CI-image deployment and explicit TestFlight UPLOAD. These are separate gates; no release success is inferred from local tests. No paid provider/TTS calls or credential replay. Physical VoiceOver, tester processing/installation and signed-in production inference remain outside synthetic acceptance.
