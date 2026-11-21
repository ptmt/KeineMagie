# Native Coach stable chat + contextual vocabulary (local candidate)

Base: remote `main` `39ed59dc534c600c1d823f573ad7c35474791c54`, verified by `git ls-remote`; previous native source `a29ea59b49bf921dd8d136b2ff0772934be81d93`. Isolated branch `candidate/coach-stable-chat`; original dirty checkout untouched. **Not published. No paid AI, production mutations, quota/budget or assessment-policy changes.**

## Presentation

- Exercise sentence/instruction stays in its own left bubble; exact submitted answer is a separate right bubble. Pending assessment is a separate left three-dot bubble. Stop replaces Send in the composer and calls the existing cancellation path with the actual attempt/request ID; the discussion draft remains independent.
- A separate assistant result shows the real verdict, literal returned correction and assessment explanation. It never manufactures a full-sentence correction from a cloze fragment. Failed/canceled/uncertain work remains distinct from wrong answers. Existing plus-menu, recheck confirmation, assistedness, review/exclude/reset, owner/cache and receipt routes are retained.
- The old rolling-day filter could omit a pending turn and leave only global checking chrome; current work was not exempt from the historical window. Pending groups are now retained, and the current exercise is pinned on the active operation independently of Earlier pagination. This reproduces a code-level failure mechanism, not a diagnosis of an unobserved production request. Earlier remains a bounded explicit disclosure; other old messages do not open automatically.
- Native runtime tests exercise old current exercise + collapsed older history, exact whitespace, correct/incorrect, transport error, Stop, discussion draft, separate discussion send, long-history bottom/own-send/Earlier navigation. Screenshots are real Release simulator UI with **explicitly synthetic transport**, not live model output. The dots are static, including Reduce Motion.

## Contextual vocabulary contract

New `kind: context_translation`, with additive optional public/native fields:

- `prompt` and `quote`: identical literal source-sentence context.
- `target_text`: unique contiguous whole word/short expression within that sentence (maximum 120 Unicode code points), not the whole sentence. Native uses bold + underline, web uses a literal-text strong element. No Markdown/HTML interpretation.
- `answer_language`: copied from the saved translation's original `source_language`; source context remains the saved translated text and its `target_language`. A missing/auto/same-language source direction cannot generate this type. Interface locale controls explanation language, **not** answer language.
- Existing narrow vocabulary skills, owner source ID and exact-quote grounding remain mandatory. Generation answer examples remain server-private; both legacy nine-field results and new eleven-field results decode, without relaxing required legacy fields.
- The strict generation schema includes the new kind/fields; non-vocabulary kinds return empty new fields. Existing types and persisted history remain valid. No local hard-coded grading or model fallback is added.
- The unchanged authenticated `answer` route persists exact learner input/receipt before inference. Its evaluator now receives target text + answer language, explicitly evaluates that target in sentence context, and accepts contextual synonyms/phrases. Tests return a **synthetic** correct judgment for `collect` although the illustrative generation answer is `pick up`; this verifies transport and persistence, not real-model semantic reliability.
- Assessment failure/duplicate/cancellation/owner fences and daily limits remain unchanged. Completion evidence is the existing durable `coachTurn.Attempt`: `assessment_state == completed` and `assessment` verdict, with its existing attempt `at`; failed/canceled/pending work adds no skill evidence. No UI completion counter or new fabricated event is emitted. The weekly-activity worker can reuse the existing Coach attempt rules (attempt timestamp is submission time, not a newly introduced assessment-completion timestamp).

### Direction limitation

Current grounded Coach sources contain translated outputs and saved podcast passages, not the paired original text as a separately addressable Coach source. This candidate translates **from the saved context language back into that record's original language**. Both German→English and English→German contracts are tested when a saved record supplies the respective context and language pair. It does not invent a learner/native language for podcasts, invert a sentence without a separately saved source, or add a synthetic reverse source ID. For a single record, practicing its original sentence in the opposite direction still needs an explicit paired-source contract; old exercise types remain available when the direction is unknown. No course-language setting changes.

## Read-only adaptation audit

`server/coach.go` supplies at most twelve saved owner sources; reserves room for saved passages, and includes up to six recent conversation entries with exercise/skill/source plus literal answer/outcome when available. The generation instruction asks for a different example for practice/more. For `more`, the server removes the latest source when alternatives exist. Thus there is **context-conditioned generation and source novelty**, not a demonstrated skill-weighted adaptive scheduler.

Observed skill aggregates count narrow targets, correct/needs-practice, assistance, distinct source examples and recency with conservative limited confidence. The progress route can recommend a next step from those saved aggregates. The ordinary exercise generation request does **not** receive a CEFR profile or multidimensional aggregate weighting, and there is no explicit difficulty/calibrated challenge field in the Coach result/source/native DTO. Therefore **no difficulty dots were invented**. A single wrong exercise is not a CEFR/level estimate; no target, self-assessment, promotion/demotion or adaptive-selection policy was changed.

## Verification receipts

RED: pending old group disappeared; missing explicit pin; instruction disappeared after answer; new type rejected; missing native target decoding; native separate answer/Stop absent; native target highlight absent; web target highlight absent; partial-word target and missing legacy array acceptance.

GREEN receipts and inspected PNGs are in `docs/coach-stable-chat-evidence/`; `.xcresult` bundles and full local logs remain under `/Users/tinyserve/.hermes/cache/scratch/coach-*`.

Verified: 21 selected Release UI cases across normal light (5), normal dark (4), SE light (4), SE dark (8), then a coherent final SE-dark run of 5/5 after retaining the original unread marker. One earlier final run was interrupted with “Test crashed with signal term” (4 passed / 1 interrupted); its receipt is retained, and the entire five-test selection passed on retry, not merely the interrupted case. Multiple workers contended for the simulator pool; active slots were checked and busy runs deferred, but a competing process appeared during some boundaries. No clones/new simulators or deliberate termination of another worker. Both borrowed devices were confirmed shut down after final export.

Other gates: full Go race + vet; Core 112 XCTest (5 existing skips) plus 84 Swift Testing; focused real AppModel harness 16; 178 Node tests (177 pass / 1 existing skip); three native Coach guards and ten real authenticated Go→Swift JSON snapshots. New Stop localization is present in all five locales; structured localization parses without duplicate keys. Added-line security scan, conflict-marker scan and git diff --check are clean. A separate independent integration review remains the parent agent's gate; this worker did not run a paid reviewer.

The local commit is recorded by the delivery report. Physical device/VoiceOver speech, production owner data, real contextual synonym quality, reverse-direction vocabulary and inferred difficulty remain unverified or intentionally unsupported. The separately developed weekly strip is **not included** in this candidate; integrate it above the transcript/below the native title without changing chat state ownership.
