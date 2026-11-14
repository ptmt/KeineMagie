# Coach contextual AI assessment candidate

Base: fresh `origin/main` at `5b871f109034c31eaa6dd0a0d919f8bda5780305` (compact Coach `03599b0`). Isolated branch `candidate/coach-ai-assessment`, worktree `KeineMagie-coach-assessment`. No deployment, push, signing upload or real provider test authorized/performed.

## Behavior and exact route

Every new explicit exercise **Check** now runs contextual AI assessment, not accepted/rejected string-list matching. Generation keeps its old example arrays for storage/wire compatibility but assessment neither sends nor consults them. The regression test deliberately puts **beim** in the old accepted array and verifies the actual handler still calls the assessment provider and saves the synthetic `incorrect` result, correction **bei**, explanation **beim = bei dem**, with **diesem** already outside the blank.

Personal authenticated owner's exact catalog must contain **`gpt-6.1-terra`**. No model fallback or shared key. Existing provider access and Responses transport: `POST https://api.openai.com/v1/responses`, `store:false`, `stream:true`, strict `coach_assessment` JSON schema, no tools, 1600 output tokens, 60-second request deadline. Uses existing cross-process shared translation attempt reservation/consumption (default 100/day); GET, view open, typing, reveal, skip and replay do not infer.

Context includes unchanged instruction and exercise prompt, kind, narrow server-saved target, source language, original quote, server-resolved owner source, learner answer verbatim, original hint-assistedness and interface locale. Original source lookup is exact, not restricted to the twelve recent generation candidates. Podcast passages must still be owner-saved and match the underlying segment; contiguous exercise excerpts are allowed. Source/prompt/answer are untrusted JSON data. Instructions explicitly accept valid alternatives, multiword and grammatical equivalents, and disallow source instructions, changing exercise/skills, external citations and CEFR claims.

Server validates all fields, types, enum values, lengths, duplicate keys, extra fields and trailing JSON. Verdicts: `correct`, `partially_correct`, `incorrect`, `uncertain`; uncertainty requires `ambiguous_exercise` or `insufficient_context`. Absent-list uncertainty is rejected as a reason. Refusals, malformed outputs, transport errors and deadlines are infrastructure failures, not learner weakness.

## Durable attempts and compatibility

- Owner-scoped receipt and exact answer are atomically saved **before** catalog or inference. Concurrent identical IDs and repeated Check with another ID return saved state without another generation, quota charge or observation. Conflicting payloads/answers reject.
- Durable sent intent precedes the existing quota charge. A crash between these operations conservatively leaves pending work; no blind replay under the same ID. A call can consume quota even if its response is lost or cancellation follows dispatch.
- Cancel accepts assessment request ID or existing turn ID, including pre-admission request-ID tombstones. Final result commits only for the still-pending matching assessment ID, under the auth-store revocation lock. Old canceled responses cannot overwrite rechecks. Browser owner assertion is additive; old clients remain supported.
- Pending/failed/canceled attempts have no new evidence. Failed or pending rechecks retain previous recorded evidence. Validated result and observations derive from one atomic saved record. No profile CEFR mutation. Rechecking retains the original answer time, exclusion and assistedness, preventing rechecks from inventing fresh learning evidence.
- Old grades remain readable; no migration silently regrades them. Explicit **Check again with AI** preserves old records in `prior_attempts` and assesses the same literal answer. Confirmation says this is a new personal AI call and previous work may already have consumed quota. A pending/crash-interrupted attempt must be explicitly canceled before recheck.
- Old `outcome` values stay `correct`/`wrong`/`ambiguous`/`skipped`; new clients use additive `assessment_state`, `assessment`, `assessment_error`, `sent`. Partial maps to legacy `wrong`/needs-practice; uncertain maps to legacy `ambiguous`. Old native decoders ignore additive fields. New clients distinguish infrastructure state instead of displaying a learner verdict.

## Clients

Compact web/native cards keep literal answer, contextual verdict, correction and explanation. Immediate quiet pending feedback; keyed web bubbles and existing source navigation/keyboard behavior retained. New labels in all five interface locales. Native persists its owner-scoped pending snapshot before transport and fences late results by generation/epoch. Server persistence is authoritative for web reload. Review controls do not turn an unassessed infrastructure failure into evidence.

AppModel edits are confined to `sendCoach`, not translation outbox behavior. Simulator fixture changes are confined to Coach. Parallel outbox/podcast candidates are not merged or modified.

## Verification

All model replies, source records, browser transports and simulator sessions are **synthetic**. No live inference quality claim.

- RED: real handler previously returned `correct` for seeded accepted `beim` with **zero provider calls**. New contextual handler test passes.
- Actual handler fake Responses tests cover exact route/context, alternative full-sentence answer, partial/incorrect/genuine ambiguity, malformed/duplicate/extra/null/trailing output, refusal, timeout, repeated answers/IDs, pending persistence, cancellation before admission, cancellation during dispatch, revocation, old owner, late old result versus recheck, catalog/no fallback, shared budget and historical evidence.
- Targeted Coach Go race suite and `go vet ./...` pass. Full Go race verification recorded below after completion.
- Node full suite: 82 passed.
- Core full suite: 18 XCTest + 68 Swift Testing passed.
- Actual AppModel temporary-package harness: 43 passed, including pending answer saved to owner cache before suspended transport and stale account-reset rejection.
- Native compact source checks: 2 passed.
- Real browser synthetic shell: passed correct/incorrect/uncertain/skip/cancel/reload, exact course correction, source translation/podcast navigation and Back, five locales, reduced motion, mobile composer and logout. Images: scratch `coach-browser/`.
- Cross-language wire check `python3 native/ci/test_coach_wire.py`: **seven actual authenticated Go-handler JSON snapshots** (initial, exercise, assessment/profile, pending, failed, legacy, reset) decoded by compiled production Swift `Coach.swift`. Coach's only required DTO arrays are `CoachSnapshot.turns` and `.observations`; `coachView` explicitly constructs both as nonnil slices. No `null`-array Coach failure reproduced. This does **not** establish a cause for a historical Coach network error or change the separate Podcast investigation.

## Limits / review gates

Schema validation cannot prove semantic correctness of natural-language explanations or fully eliminate prompt injection; there is no hardcoded accepted-answer replacement masquerading as AI. Synthetic tests prove dispatch, context, persistence and handling, not live grading quality. A separately authorized live interaction remains necessary for model-quality evaluation. Existing quota charge and Coach JSON are separate durable files; crash windows intentionally fail closed rather than claiming transactional exactly-once across provider and local storage. Server restart leaves pending IDs requiring explicit cancel/recheck. Existing history limit and receipt limit remain (250 turns / 10,000 receipts). No automatic background polling/inference.

Independent review performed locally; parent must coordinate integration with the independently pushed Podcast candidate before merge/release. No remote write was performed by this reviewer.

### Completed execution evidence

- Full `go test -race -timeout 8m ./...` **passed** (361.999 s); `go vet ./...` passed. An earlier concurrent full run timed out at 240 s; another hit the existing Podcast SIGKILL translation wait (17 s). That unrelated test passed alone (12.481 s) and the full rerun passed. Latest targeted Coach race suite also passed after passage/excerpt and same-answer evidence refinements.
- Ad-hoc-signed **Release UI: 7 tests passed**, zero failures/skips/runtime warnings, isolated iPhone 17e iOS 27.2 `73A7FD9E-7F56-4E2F-957D-68E1FADA7436`. Includes new contextual pending/correction regression, five locales, original-source navigation, profile correction, large text and real keyboard composer reachability. Result: scratch `coach-assessment-release-2.xcresult`; exported attachments: `coach-assessment-attachments/`. Visually inspected pending and corrected screenshots: literal **beim**, no mistake verdict while pending, **Incorrect**, **bei**, and contextual explanation after completion. Existing large-text test is not independent proof of actual dark system appearance.
- Initial foreground Xcode command exceeded tool transport wait without a complete result bundle; rerun as tracked background produced the verified xcresult above. Python system interpreter lacked Playwright; `uv run --with playwright python web/tests/coach_browser.py` passed.
- After screenshot inspection, removed duplicate global pending decoration for assessment cards (the card itself owns quiet pending/cancel feedback). Final targeted signed Release regression passed (1/1, no warnings) in `coach-assessment-final.xcresult`; inspected final pending screenshot confirms one Cancel and no extra global spinner. Full Node 82, browser and seven Go→Swift snapshots re-passed afterward. Native localization checks: 7 passed.
- Final full-race reruns encountered intermittent failures outside Coach: `TestPodcastSIGKILLRecovery/download` (completed media retained: 1) and `TestAppleWebSignedCodeLogin` (callback 401); no Coach test failed. These tests/files are untouched. Earlier full race passed; latest full serial-scheduling race result is recorded below rather than masking intermittent failures.
- **Final artifact:** `go test -race -parallel 1 -timeout 8m ./...` passed (**113.417 s**) and `go vet ./...` passed. All tests retained, only test-run scheduling serialized. `git diff --check` and signed Release app `codesign --verify --deep --strict` passed. Independent review/merge/release remain with parent; worktree intentionally uncommitted at that stage.

### Independent review and local fixes

- Reviewed all original 21 candidate paths, actual handler serialization and production Swift decoding. No Coach null-array failure reproduced in seven handler snapshots; this does not diagnose any prior network error.
- Found and reproduced native answer preflight silently ignoring cache write failure. RED actual-AppModel test replaced the cache directory with a regular file: POST still occurred and the literal answer disappeared. GREEN now requires successful pending-snapshot encoding/write before assessment transport, retains the literal answer with `coach.error.storage` on failure, and keeps account/epoch fences. Simulator-only cache-disabled synthetic fixtures remain exempt from disk writes.
- Found and reproduced logout cleanup omitting the Coach dataset (pre-existing cleanup allowlist, now storing pending literal answers). RED Core test retained 22 bytes after cleanup; GREEN includes `coach` in the same owner/session-fenced cleanup. Other dataset behavior unchanged.
- Fresh verification after fixes: full uncached `go test -race -count=1 -parallel 1 -timeout 8m ./...` passed (74.427 s), vet passed; Core 19 XCTest + 68 Swift Testing passed; actual AppModel harness 44 passed. Node 82, real synthetic browser, localization 7 and compact 2 checks passed during review; seven actual Go-handler snapshots re-decoded after fixes. No real provider inference performed.
- Rebuilt ad-hoc-signed Release and ran contextual pending/correction UI regression: 1 passed, zero failures/skips/runtime warnings. Result `/Users/tinyserve/.hermes/cache/scratch/coach-assessment-independent-review.xcresult`; freshly exported/visually inspected screenshots in `coach-assessment-independent-review-attachments/` show literal `beim`, one local Cancel while pending, then Incorrect / `bei` and complete explanation. Signature and diff whitespace checks pass.
- Local tracking ref advanced independently to Podcast `d3f2261499a5317b89055343fef61ff9297fe564`. Reviewer did not fetch, push, merge, rebase, deploy or touch other worktrees. Parent must preserve both clients' additions when integrating shared AppModel, localization and simulator-fixture files; run integrated gates afterward. Candidate is ready for that integration, not a live-model-quality signoff.
