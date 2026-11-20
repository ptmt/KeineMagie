# Local candidate: manual sentence pacing (policy 2)

## Observed source, not a cache diagnosis

The supplied web image shows the **legacy** branch: `Pause`, manual `Next`, legacy step 1/23, and the legacy hint. Released policy 1 is a distinct opt-in attempt protocol: whole mode by default, a sentence/chunk/sentence-repeat plan, automatic 3-second transitions, and a separate durable playback ledger. Replacing only the hint would be false. Native currently supports policy 1 and disables unknown policies.

## Requested policy 2

- New web attempts explicitly opt into version 2, default to sentences, and begin with the whole-text introduction only on Play. That introduction uses the existing four-whole-start allowance. Opening never plays or prepares audio.
- Each conservative punctuation-delimited fragment plays twice (optionally three times), with 3-second or extended 8-second gaps **between repetitions only**. After introduction and each completed fragment the primary transport slot becomes Next. There is never automatic advancement to another fragment. Optional final whole reading remains explicit and shares the existing allowance.
- Primary slot shows Stop while playing/waiting, Next while writing, and Prepare only for missing assets. Status names the actual phase/repetition and upcoming fragment. A compact expandable timeline distinguishes confirmed ended receipts from admission starts; Stop is not completion.
- Existing attempts keep their stored policy, mode, drafts and audio. An explicit upgrade must preserve old plan/ledger history, existing asset identities and whole-start/final allowances; new fragment audio is prepared only through the existing explicit Prepare action.
- Sentence/clause splitting is deterministic punctuation heuristics, not semantic NLP. No blind comma/word-count cuts; abbreviations, decimals and quoted text require fixtures.
- Policy 0/1 behavior remains unchanged. Native must preserve v2 fields and fail closed with an honest compatibility message until native transport/UI parity is verified. A shared backend is not native UI parity.

## Assessment wire contract (additive; grading files untouched)

- `playback.listens[]`: unique durable `id` identifies an admitted start; owner and attempt are the authenticated record scope. Policy 2 adds `policy_version: 2`, `asset`, and `intent: "planned" | "extra"`. Plan step plus asset preserves fragment identity across configured repeats. An explicit extra replay is one additional cached clip, does not advance the cursor, and does not use a whole-text start.
- `ended: true` means the client reported natural media completion and the server accepted it under the ownership fence. It is **not proof a human heard it**. `done` alone is not completion: legacy cancel uses that field too. `stopped` is terminal without completion. Missing `intent`/`ended` on historical entries means unknown, never infer zero extras or completion.
- `resumes`, `interruptions`, `play_failures` are additive counters on the same policy-2 admission. Resume does not create another replay/start. Planned repetitions are not extra help or a penalty. `stop_base`, `fence`, leases, original stop operation IDs and exact pending stop request bodies remain authoritative for recovery.
- `pacing_history` is private server-only archived old plan/ledger on explicit upgrade, including old whole-start counts. Public responses omit it to avoid leaking the original text. Current `whole_starts`/`final_used` survive upgrade. Grading code needing old evidence must read the owned server record and interpret its archived version, not reinterpret old indexes against the new plan.
- `GET /v1/learning/dictations` adds `speech_spend`: `month`, `currency: "USD"`, `scope: "owner_attributed_speech_receipts"`, nullable `reported_micro_usd`, `unsettled_reservations`, and separate `reserved_micro_usd`. It is **not all-AI spend**. Pre-attribution global receipts cannot be assigned to an owner and are excluded. Never substitute the global $10 reservation total for reported spend or missing receipt data for zero.

## Budget admission finding and deliberately bounded fix

The existing monthly guard reserves $1 for every uncached asset attempt, retains the full hold even with a usage receipt, and admits at most ten such attempts per UTC month. Clause plans can exceed that count. This candidate does **not** raise the cap, settle/refund existing holds, rewrite historical production receipts, or claim that usage-reported spend unlocks more calls. A broader cost-ceiling/receipt-settlement design is a separate release blocker.

The bounded admission fix holds the monthly lock while checking/reserving the daily allowance, inside the existing authenticated owner transaction. Normal monthly, daily or owner-limit rejection does not consume the other allowance. No provider call occurs until all reservations commit. A crash or filesystem failure after an earlier reservation commit conservatively retains that reservation; no ambiguous reservation is refunded. Lock order: auth → owner history → monthly → global daily. UI 429 now identifies an audio limit instead of suggesting a generic preparation retry. Partial existing audio is not regenerated automatically.

## Verification boundaries

Local only. No deployment, push, paid AI/TTS, production data, protected original worktree, Coach worktree, AnyProgress, or concurrent simulator use. Synthetic WAV/media evidence establishes transport behavior, not speech quality.

### Executed verification

- `go test -json -race ./...`: 603 passing test events including subtests (309 top-level passing tests); 15 opt-in/skipped tests, no failures. `go vet ./...` passes.
- `node --test web/tests/*.test.mjs`: 174 tests, 173 pass, one skip, no failures.
- `swift test` in `native/Core`: 102 XCTest cases with four skips and no failures, plus 84 Swift Testing cases passing. Native localization contract script also passes. No simulator or native policy-2 UI playback validation is claimed.
- `web/tests/dictation_manual_pacing_browser.py`: real Chromium media events against the Go fixture, synthetic silent WAV only. Verifies 2/3 repetitions, 8-second extended gap, no auto-next, explicit extra replay without cursor/whole-start debit, optional final reading, exact lost-Stop-ACK recovery after reload, retained writing, and equal primary Stop/Next geometry once fragment media starts. Checks all five locales at 390/1100 widths. Twelve actual captures and machine-readable result are under `docs/evidence/dictation-manual-pacing/`.
- Existing `web/tests/dictation_policy_browser.py` also passes against the final candidate; its generated legacy evidence was restored rather than mixed into this change.

### Boundaries / release gates

- Native preserves new data and explicitly refuses policy-2 transport; native transport/UI parity is still a separate release gate. Do not advertise cross-platform feature parity from Core tests.
- This is not a complete offline media-event outbox. The durable ledger describes server-accepted admissions and reports, not unreported offline playback. Lost/unaccepted natural-end or interruption observations remain unknown; assessment must not infer them or penalize missing evidence. Exact Stop recovery remains durable. Counters are accepted ownership actions, not proof of audible human listening.
- Pacing retains the existing bounded source/asset space: at most 59 fragments, two or three plays, and asset IDs at most 120. An upgrade that cannot fit is rejected without overwriting old assets or history.
- The global historical receipt amount cannot safely be attributed to an arbitrary owner. Existing unattributed-only history therefore displays no owner-spend data rather than inventing `$0` or leaking the global figure. New owner-attributed receipts populate the footer. LLM costs are not included.
- The current reservation guard can still block preparation despite low reported actual cost. This patch does not settle old holds or resolve the broader actual-cost ceiling design.
- Pre-v2 typed server writers are not safe rollback targets after new metadata exists. Any rollback must preserve pacing/history, replay evidence, stop receipts and owner attribution; do not restore old user data.
- Independent integrated review and native UI verification remain outstanding before any release. Assessment implementation belongs to its separate worker; no grading/diff behavior was changed here.
