# Summary diagnostics and episode coverage

Initial candidate inspection below was read-only: no deployment, push, production mutation or provider inference. The independent release record at the end supersedes candidate-only status; no paid inference is part of this release.

## Evidence and scope of diagnosis

- Inspected both supplied screenshots. Summary shows **Not generated**, **51 remaining**, a muted Generate button and **Cancel**. In this implementation Cancel is rendered only when `generation` exists: this is an active explicit operation, not evidence that the user forgot to click Generate.
- Read-only running-container diagnostics: current image prefix `931a28e2785b`; one completed job, 2,113 saved segments and 2,113 translations, empty job error.
- Sanitized existing access logs show one analysis GET and two analysis POSTs (22.52 s and 37.67 s). Logger records elapsed time but **not response status/error**. No private text or identities printed.
- Read-only learning storage has one analysis checkpoint with one saved step. Independently reconstructed the current context key in memory (source-only transcript digest, current CEFR and vocabulary): **that exact current context checkpoint exists and contains one step**. No provider/auth/session/secret stores were read or replayed.
- Therefore the event→POST→durable-checkpoint path **did run**, but the full summary has not completed. The exact reason the second live request stopped is **unknown**: provider rejection, incomplete/invalid output, cancellation and other failures cannot be distinguished from retained logs. No assertion that paid inference is fixed is justified.

### Proven presentation defects, fixed with red→green tests

`button.onclick → generate → createAnalysisRunner → createEpisodeClient → POST analysis → learningAnalysisHTTP → checkpoint → response → draw`.

1. During an outstanding initial POST, draw kept showing **Not generated** even while Cancel existed. Regression failed waiting for `Generating analysis…`; now running status appears immediately, with saved/total steps.
2. All failures were collapsed into `Could not load. Try again.` outside Summary; raw server error text was intentionally discarded by `createAPI`. Added safe machine-readable failure-stage codes server-side and localized actionable messages **inside Summary**, never rendering provider payloads. Regression failed on absent `analysis_invalid_output`; now passes.
3. Display the actual saved-step denominator and explicit Resume; do not retry paid failures automatically. Completed checkpoint behavior, cancellation, navigation stop and bounded serial authorization unchanged.

## Episode rows and actual data model

Existing favorites were only **vocabulary words/idioms**, not sentences. Recognition segments may contain several sentences. This candidate deliberately says **passages**, not fabricated sentence or listening progress.

- Add optional `coverage` to owner job list/detail/permalink responses: `recognized_segments`, `translated_segments`, `favorite_passages`, optional `favorite_segment_ids`.
- Coverage counts trimmed nonempty saved translations, with denominator equal to **currently saved recognizer segments**, not an invented eventual full-episode total. Unprepared rows retain Prepare with no false 0/0 total.
- New explicit `PUT /v1/learning/episodes/{job_id}/passages/{zero-based-index}` with body `{"favorite":true|false}`. Uses existing owner auth, same-origin/CSRF and locked learning store. Idempotent, bounded; validates canonical index and owner transcript. Marks are grounded against exact current source text and deduplicated. Word/idiom favorites are never counted.
- One owner learning-store transaction plus in-memory per-job grouping enriches the whole library. No per-episode learning requests. Transcript/podcast readiness remains independent if learning storage fails: omit unknown coverage rather than hide saved transcript or fabricate zeros.
- Transcript gets explicit Star/Unstar passage, followed by exact job GET readback. Feed navigation refreshes actual counts.
- Five interface locales; quiet metadata `Translated n / total segments · Starred n / total passages`. No vocabulary progress, listening completion or CEFR advancement is inferred.

## Executed verification

Red then green:
- `episode_diagnostics_browser.py`: initial running text missing → passes running state, safe actionable error, locale preservation, no automatic retry, no stale Cancel, explicit saved-step Resume.
- `TestLearningAnalysisFailureReturnsSafeStageCode`: no error code → passes safe invalid-output code and no fabricated checkpoint/replay.
- `TestPodcastLibraryCoverageAndPassageFavoritesAreOwnerScoped`: missing coverage → passes separate vocabulary/passages, owner isolation, idempotent mark/unmark and invalid IDs.
- `podcast_coverage_browser.py`: missing row counts → passes counts, unknown unprepared denominator, no N+1, five locales, mark and feed readback, 320px overflow gate, no inference.
- `TestPodcastCoverageFailureDoesNotBlockIndependentTranscript`: 503 → passes independent saved transcript and unknown coverage omission.

Final runs:
- `go test ./...`, `go vet ./...` passed.
- Targeted learning/coverage/passage `go test -race` passed.
- `node --test web/tests/*.test.mjs`: 69 passed (existing Node experimental localStorage warning only).
- Browser: analysis lifecycle, diagnostics, coverage, episode navigation, episode review (20 locale/width combinations), podcast design (50 rows, four widths, light/dark) passed; zero page errors.
- `git diff --check` passed.

Inspected synthetic browser screenshots (not production evidence):
- `/Users/tinyserve/.hermes/cache/scratch/summary-running-synthetic.png`
- `/Users/tinyserve/.hermes/cache/scratch/summary-error-synthetic.png`
- `/Users/tinyserve/.hermes/cache/scratch/summary-diagnostics-synthetic.png`
- `/Users/tinyserve/.hermes/cache/scratch/podcast-coverage-synthetic.png`

## Independent review and release verification — 2026-11-13

Reviewed the complete tracked diff and every new server/test file independently of the implementation. Passage mutations inherit owner authentication and exact-origin/session-CSRF checks before routing; canonical indices, strict bounded JSON, owner transcript lookup, owner-hashed storage, atomic flocked updates, deduplication and exact source matching keep marks separate from vocabulary. Aggregation is O(saved segments + passage marks + jobs), one owner learning-store read; no per-row HTTP/store reads. Read failure omits unknown coverage. Safe analysis codes are fixed literals, never upstream text. Explicit bounded serial generation, cancellation, account/navigation fences and checkpoint-only GET remain intact.

Two substantive review fixes (each reproduced RED then GREEN):
- Feed-associated **direct imports** previously fell back to subscription preparation objects, which deliberately omit transcript/coverage. Resolve the preparation ID against the enriched owner job before fallback. Added real Node regression.
- Failed initial checkpoint GET discarded the new diagnostic code. Summary now shows the same localized safe actionable error for GET and POST, clears it on successful read, and never exposes storage paths. Added Chromium regression.

Fresh independent verification: full `go test -race ./...` passed (37.583s), `go vet ./...` passed, all **70 Node tests** passed (existing localStorage experimental warning only). Diagnostics, coverage, analysis lifecycle, episode navigation, episode review (20 locale/width combinations), and podcast design (50 rows, four widths, light/dark) Chromium suites passed, no page errors. Added missing-Origin CSRF denial case; owner/idempotency/current-source regressions pass under full race. `git diff --check` passed. Synthetic screenshots inspected; not production private-owner evidence.

## Remaining acceptance

An explicitly owner-authorized live Resume (could consume remaining requests) is needed to establish live provider behavior/full completion. This release improves truthful feedback and diagnosability; it does **not** claim the unknown live inference failure is solved. Per-sentence favorites would require genuine sentence segmentation/identity semantics; current UI intentionally exposes real segment-level passage marks. Native client does not yet display these new coverage/mark controls.
