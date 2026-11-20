# Dictation assessment and progress

## Product contract

Dictation measures **fidelity to an unchanged recording reference**, not general language level. Linguistic correctness is a separate explanation: a grammatical paraphrase can still differ from what was dictated. The original source and the literal learner answer are never rewritten by an LLM.

An unfinished answer is not a failed full dictation. By default Check compares the answered prefix and groups the unmatched ending under **Not yet attempted**. The learner can explicitly select **I finished the whole text**; only then are omitted ending words counted as omissions. Gaps inside the aligned answered portion remain omissions. This is a conservative text-alignment boundary, not proof of which audio the learner heard. An unrelated answer or repeated words can make prefix alignment uncertain; the UI shows coverage, not a misleading whole-text success percentage.

Check is explicit. Opening, reloading, changing locale, reading history, or recovering a result never sends inference. No automatic rechecks after an error, crash, cancellation or uncertain timeout.

## Implemented local vertical slice

- Actual authenticated Go handlers, durable owner-scoped storage, existing configured provider integration, actual web module and responsive rendering.
- `POST /v1/learning/dictations/{id}/check` accepts existing `revision`, plus optional `hybrid`, `complete`, `locale`. Updated web sends `hybrid: true`. Older clients can omit it and receive deterministic comparison only.
- The first Check freezes source, answer, submitted revision, timestamp, original assistance and algorithm version in an additive `assessment` receipt. The record remains checked/immutable; new attempts retain their own distinct IDs and old receipts.
- Repeated Check on an already checked attempt returns its saved record; it never spends quota again or changes the original complete/partial declaration. There is deliberately no same-attempt paid retry endpoint in this slice.
- `GET /v1/learning/dictations/{id}` is result recovery. `POST .../{id}/cancel-assessment` with the submitted revision cancels pending explanation. Pre-admission cancellation stores a durable tombstone for that attempt/revision.
- An additive `progress` object in the owner library GET returns retained distinct-attempt entries and aggregate counts. Existing clients ignore unknown fields. No private source or answer is added to library rows/progress.
- Swift has additive Codable DTOs tested against **actual Go-handler JSON**. This is not a native UI implementation, native hybrid-Check opt-in, or a native release.

## Deterministic alignment

`server/dictation_alignment.go` tokenizes words and punctuation with exact UTF-8 byte offsets. NFC normalization and case folding are used only for alignment cost; neither persisted string changes. A dynamic-programming edit alignment finds the least-cost reference prefix for partial submissions. Full submissions align against the entire reference. Adjacent operations become stable span IDs (`s0`, `s1`, … within one immutable receipt).

Each span includes source/answer start/end byte offsets and literal slices. Concatenating all original slices reconstructs the exact source; concatenating all written slices reconstructs the exact answer, including whitespace and composed/decomposed Unicode. Byte offsets are **not** JavaScript UTF-16 or Swift Character indices: clients render the supplied literal slices.

Kinds: equal, omission, addition, substitution, spelling (case difference), punctuation, unattempted. Grammar/meaning judgments belong to the explanation layer, not a guessed deterministic rule. This is word/punctuation alignment displayed in source sentence context; it does not resegment or rewrite the audio plan and does not claim a separate semantic sentence-alignment model.

The web displays source and answer as inline passages (side by side on desktop, stacked on narrow screens), compact category labels and one closed, scroll-bounded unfinished-ending disclosure. Legacy results are grouped in closed details rather than one paragraph per token. The legacy `differences` projection for new receipts excludes unattempted suffixes, so older consumers do not count those endings as mistakes. Historical receipts are not silently recalculated.

Raw metrics remain inspectable: exact words, attempted reference words, source words, omissions, additions, substitutions, and unattempted words. Punctuation is visible but not a word. Exact-word counts are case-sensitive but treat canonically equivalent Unicode as the same spelling; original bytes remain untouched. No replay penalty, invented accuracy percentage or global level is applied.

## LLM boundary, privacy and limits

The existing Coach model constant (`coachModel`, currently `gpt-6.1-terra` in this repository) is reused explicitly. Account access is resolved for the authenticated owner, and the exact model must appear in that account's catalog. There is no first-available model selection, global personal credential fallback, alternate provider, or invented endpoint. Public model existence and live pedagogical quality have **not** been verified by this local work.

The bounded request uses the existing Responses transport with a 60-second context, no tools, `store: false`, 2,000 output tokens and a strict schema. It includes the exact reference, answer, aligned evidence and interface locale. Original/source text and answers are untrusted data, not instructions.

The result is at most 12 notes with an allowlisted category, existing span ID, exact source/answer quotes and bounded plain-text explanation. Validation rejects unknown/duplicate span IDs, changed quotes, unattempted-suffix claims, unknown fields, duplicate JSON keys, trailing JSON, null note arrays and explicit CEFR/A1–C2 claims. It validates evidence correspondence, **not the truth of every natural-language pedagogical statement**; the explanation remains labeled AI output. No output can replace the authoritative source or deterministic metrics. Provider/user text is rendered via `textContent`, never HTML or Markdown.

Before catalog/network work, the owner receipt and verbatim evidence are committed to disk. A durable dispatch-intent flag precedes quota consumption. A duplicate or process restart cannot dispatch the same receipt again. Final persistence rechecks authenticated-session validity, active receipt identity and pending state. Cancellation/deletion/revocation fence late acknowledgements. A request already dispatched may still consume upstream resources after cancellation. A process killed with a pending receipt leaves an honest pending/unknown result; GET does not retry it.

LLM assessment consumes **one existing owner translation/Coach allowance** (`reserveTranslationPlan`, including configured daily limits). A refusal is `llm_quota`, distinct from speech preparation's shared monthly **US$10 audio budget**. This work does not raise either limit or estimate actual dollar spend. The separate pacing/spend worker owns the shared actual-spend footer and speech budget fixes; its worktree was not edited.

Timeout, malformed model output, missing connection/model, quota refusal and cancellation preserve the answer and deterministic comparison. They are infrastructure/assessment states, not learner mistakes. Source/answer remain owner-private; unchecked, unrevealed sources are still redacted. Explicit pre-submission source reveal counts as assistance; later reveal cannot rewrite the frozen receipt's assistance.

## Replay evidence and learning progress

See `DICTATION-REPLAY-CONTRACT.md` for the integration proposal supplied to the parallel pacing worker.

Keep separate per original segment:

1. Planned repetitions (the default two are normal exercise policy).
2. Extra explicitly requested replays, deduplicated by durable operation ID.
3. Accepted playback starts.
4. Ended/completed acknowledgements.
5. Stop/interruption and resumed existing playback.

Resuming one playback is not a new extra request or completion. A start is not proof of physical listening. Missing historical tracking is **unknown**, never zero. Assessment now snapshots an additive `assistance_summary` using the reviewed pacing candidate `ec47272` wire contract. The standalone policy-0/1 branch still records `replay_tracking: "unknown"`; the adapter maps policy-2 accepted admissions to `partial`, never complete physical-listening evidence. It distinguishes planned/extra starts, confirmed ended reports, stopped/interrupted/resumed actions and unknown completion, and flags private archived history as unknown rather than reinterpreting old indexes. The saved source/audio segmentation is unchanged. The adapter has synthetic contract tests; a careful merge and real policy-2 handler integration test remain necessary.

Progress uses deterministic evidence even when the optional explanation is unavailable. The library summary counts distinct attempt IDs, distinct exact-source digests, partial attempts, attempted/source coverage and unknown historical/replay evidence. Each entry retains check time, source-reveal assistance and raw counts, enabling dated trends without merging retries into new evidence. Repeated attempts on one text are not distinct examples. Legacy checked records without receipts remain a separate unknown count, not fabricated prior scores.

Future trends should compare like-for-like coverage and assistance across distinct examples; show sample count, recency and uncertainty. Do not turn repeated rehearsals into broader mastery, subtract arbitrary replay points or infer listening/speaking/global CEFR from a partial written dictation. This slice exposes durable evidence and per-check presentation; a new longitudinal progress dashboard is not implemented.

## Local verification and boundaries

All provider tests are **synthetic/mock transport**. No real credentials were used; no paid LLM or audio request was made. Browser screenshots are the actual local application using its authenticated Go handlers and durable storage, not a static HTML mock. Synthetic provider explanations are visibly labeled and include an inert literal-markup probe.

Commands (repository root unless noted):

```sh
(cd server && go test ./...)
(cd server && go test -race ./...)
(cd server && go vet ./...)
node --test web/tests/*.test.mjs
# Generate actual Go JSON, then verify production Swift decoding:
(cd server && DICTATION_ASSESSMENT_FIXTURE=/absolute/scratch/wire.json go test -run TestDictationAssessmentWireFixtures -count=1)
(cd native/Core && DICTATION_ASSESSMENT_FIXTURE=/absolute/scratch/wire.json swift test --filter Dictation)
# Run these concurrently; use a fresh writable scratch directory and Playwright Python:
(cd server && DICTATION_ASSESSMENT_BROWSER=/absolute/scratch/browser go test -run '^TestDictationAssessmentBrowserFixture$' -count=1 -timeout=6m)
DICTATION_ASSESSMENT_BROWSER=/absolute/scratch/browser python web/tests/dictation_assessment_browser.py
```

Coverage includes partial/internal omissions, complete declarations, exact Unicode offsets, punctuation alignment, grouped long suffixes, saved receipt before catalog/inference, double-tap idempotency, preflight/inflight cancellation, late acknowledgements, owner isolation/session revocation, model entitlement/no fallback, LLM allowance refusal, provider failure, GET-only reload recovery, strict grounded notes and actual Swift decoding of unchecked/pending/completed/failed handler records.

### Executed candidate checks

- Full Go package `go test -race ./...` and `go vet ./...`: passed. The non-race full package suite also passed during implementation.
- Node suite: 168 tests, 167 passed, one skipped, no failures.
- Swift Dictation selection: 58 XCTest cases, three opt-in fixture skips, no failures; three additional Swift Testing cases passed. The new actual-Go receipt bridge ran (it was not skipped).
- Real authenticated Go + Chromium harness: four explicit checks, synthetic provider only; partial/pending/failed/GET-recovered/complete/canceled states, inert markup, owner-private pre-check source, English/Russian locale switching, 390px overflow check and a **54-word unfinished suffix** in one closed disclosure.
- Seven actual captures and the machine-readable browser result are in `docs/evidence/dictation-assessment/`. They use synthetic text/provider output and are not live model-quality evidence.
- The initial browser run failed because its fixture lacked matching `WEB_ORIGIN` (403 CSRF/origin denial). The fixture origin was corrected; the actual browser harness subsequently passed. No production authorization was weakened.
- Independent combined-branch review remains a release gate; these are isolated-candidate checks, not proof of integrated pacing/native parity.

Remaining integration gates: merge pacing candidate `ec47272` and exercise its actual policy-2 ledger through the assessment handler; integrate its owner-attributed speech-spend footer without claiming all-AI cost; native policy-2 transport/UI plus native comparison UI and explicit hybrid Check opt-in; broader pedagogical alignment/LLM quality review. The pacing candidate fixes admission order only: existing monthly reservations still block and settlement remains unresolved. Historical global speech receipts cannot be attributed to an owner and must remain No data. The user’s current inability to finish dictation is not fixed in production. No publication, push, deployment or release is authorized by this local implementation.
