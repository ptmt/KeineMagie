# Replay evidence contract and integration boundary

Assessment consumes an additive `assistance_summary` snapshot per immutable attempt/check; playback remains owned by the pacing implementation. Pre-submission source reveal remains the separate frozen receipt field `assisted`. The reviewed candidate's actual wire mapping is specified below.

```json
{"version":1,"tracking":"partial","scope":"server_accepted_reports","unreported":"unknown","archived_unknown":false,"unknown_admissions":0,"segments":[{"segment_id":"policy2:step1:asset1","step":1,"asset":1,"planned_repetitions":2,"planned_started":2,"extra_requested":0,"started":2,"completed":1,"stopped":1,"resumes":0,"interruptions":1,"play_failures":0,"completion_unknown":0}]}
```

- `tracking`: `partial` for policy-2 server-accepted evidence, or `unknown` for historical/missing contracts. Missing historical ledgers are unknown, never measured zero.
- Stable segment identity is tied to the unchanged original source/plan. Clause playback fragments may map to an original segment; they do not rewrite grading text or offsets.
- Planned repetitions (including the default two) are not extra assistance. `extra_requested` counts explicit additional replay admissions once per durable operation ID, not tap attempts/network retries.
- `started` means accepted playback start, not physical listening. `completed` means ended acknowledgement. Stop/interruption does not increment completion. Resuming the same playback ID does not increment starts or extra requests.
- Counts are owner-scoped, attempt-scoped, durable and idempotent. Duplicate/lost acknowledgement retries must not double count. Preserve canceled/unknown admission boundaries conservatively.
- Capture this summary at Check; later playback cannot mutate the assessment receipt. Keep raw dictation fidelity and assistance separate; never subtract arbitrary points for replays.
- Progress compares distinct attempts and distinct source examples, with coverage, assistance, dates and uncertainty. Repeat checks are not new attempts; no global CEFR inference.

## Reviewed pacing candidate and implemented adapter

The authoritative local pacing candidate is `ec47272`, branch `candidate/dictation-manual-pacing`, with contract documented in its `docs/dictation-manual-pacing.md`. Its actual tagged `dictationListen`/plan types were read, not guessed. No file in that worktree was modified.

`server/dictation_assistance.go` now consumes that **server-owned JSON shape** and freezes `assessment.assistance_summary` at Check. It maps `playback.listens[]` (`id`, `policy_version`, `step`, `asset`, `intent`, `ended`, `stopped`, `resumes`, `interruptions`, `play_failures`). Repeated admissions are deduplicated by ID. `done` is deliberately ignored: it also represented canceled legacy playback. Plan `sentence_repeat` steps map back to the preceding original fragment anchor with the same asset. Segment identity includes policy, anchor step and asset; it is not just an asset ID, because identical text can reuse an asset at multiple source positions. Planned repetition count comes from the saved plan, not a hardcoded default.

Only `ended && !stopped` increments confirmed completion. Active/unreported outcomes remain `completion_unknown`; resumes do not add starts or extras. Explicit `intent: extra` increments accepted extra requests once. Older/missing policy/intent/asset evidence remains unknown. Private `pacing_history` is detected as `archived_unknown`; old indexes are never reinterpreted against a new plan. Current summaries remain `tracking: partial`, `scope: server_accepted_reports`, `unreported: unknown`: the pacing candidate is not a complete offline media-event outbox.

The standalone assessment branch remains based on origin/main policy 0/1 and honestly emits unknown replay data. The adapter is wire-compatible without importing/duplicating the pacing types; synthetic actual-contract fixtures verify its mapping. **Actual policy-2 handler integration still requires a careful local merge/cherry-pick and integrated tests**. Do not deploy this pre-v2 typed writer against v2 storage: it would not preserve the pacing candidate's additional record metadata. No cross-branch cherry-pick has been performed here.

Release gates shared with the parent: native policy-2 transport is intentionally disabled in the pacing candidate; native assessment UI/hybrid Check opt-in is also incomplete. Existing speech reservations still block even with low reported cost; the candidate only fixes admission order, not settlement/refund of old holds. Its owner-attributed speech footer excludes historical unattributable global receipts and LLM spend. The current production inability to finish a dictation has **not** been fixed or released by these local candidates.
