# Local candidate: conservative speech receipt settlement

**Follow-up:** [Durable attempt prevention](dictation-attempt-prevention.md) supersedes the transport-completion and prospective admission behavior described below. This document retains the earlier settlement evidence and limitations.

Base: `ec47272`; confined to the dictation-manual-pacing worktree. No deployment, push, paid provider call, production ledger read/write, Coach edit, assessment edit, or Simulator use.

## Outcome and remaining historical blocker

The application cap remains **10,000,000 integer microUSD per UTC month**. Admission now sums validated settled costs plus full unresolved $1 reservations, instead of rejecting the eleventh ledger entry. The original reservation amount and every receipt remain stored. Monthly-before-daily lock ordering is unchanged.

This is a functioning **prospective settlement candidate**, not a claim that the reported historical block is resolved. Inspection of the prior writer shows it recorded `response.done` usage before checking completion status, including incomplete/cancelled responses, without storing response ID/status/model/rate proof. An old numeric receipt cannot distinguish those outcomes. The synthetic 40,404-microUSD scenario admits further calls only when all ten receipts also have matching completed-response proof. The same numbers without that proof still account for $10 of holds. Do not fabricate proof or infer an owner to unblock it.

There is intentionally no production migration command. `dictationMonthlyAccounted` is a pure dry-run/accounting function. Historical migration requires independently provable reservation/month/response/usage matches and an independently reviewed authorized procedure; none were available or invented here. Merely deploying this candidate will not release the ten unproven historical holds.

## Bound and receipt contract

- Official model page checked on 2026-11-20: `https://developers.openai.com/api/docs/models/gpt-realtime-2.1-mini`. It lists 128,000 context, 32,000 maximum output tokens, text input/output $0.60/$2.40 per million, audio input/output $10/$20 per million. This application sends text only, no tools or audio input, with configured output at most 4,096 tokens. The unchanged $1 hold conservatively exceeds the broader text-input/audio-output envelope used by the existing guard.
- Rate card `realtime-mini-2026-11-20` uses integer tenths of microUSD and rounds each receipt upwards. Cache discounts are ignored. This is an application accounting limit under pinned assumptions, **not an invoice guarantee** covering price changes, taxes, unrelated services, or invoice posting dates.
- The production WebSocket transport settles only after a matching response ID, `completed` status, provider audio/transcript terminal events, bounded PCM and lexical narration validation. It passes complete token breakdowns into the reservation-bound callback. No provider retry was added.
- Server-only `settlement` metadata includes version, currency, model, rate card, completed status, response ID, month and reservation ID. The existing usage and reported cost must recompute exactly. Foreign/stale/duplicate response proof, conflicting retry receipts, unsupported currency/modality, negative amounts, missing breakdowns and overflowing token detail are rejected. Original hold IDs must be unique.
- Receipt and effective settlement are one locked fsync/rename transaction, not a two-file release. Before that commit, a crash or write failure retains the full reservation; after it, an exact replay is idempotent. Audio publication can still fail after a trustworthy receipt: billing evidence does not prove a usable cached artifact. No automatic regeneration is introduced.
- Historical usage-only, incomplete/cancelled/missing/uncertain results keep the reservation. The daily duration/request guard is still conservative and is not refunded by monthly settlement.
- Receipt history is retained, not compacted or erased. Its bounded file capacity is now 4 MiB rather than the ten-attempt-era 64 KiB; this is **not a money-cap change**. Oversized writes are rejected before replacing the readable prior ledger.

## Owner footer versus global admission

The $10 guard is global to this application store. It is not a user's personal allowance. Public `speech_spend` remains `scope: owner_attributed_speech_receipts`, never a global spend endpoint. It excludes unattributed/foreign entries and stays nullable when no attributable receipt exists.

Public spend semantics are preserved: `reported_micro_usd` is an owner-scoped receipt estimate, not all-AI spend; `reserved_micro_usd` is the sum of original owner-attributed reservations; the existing `unsettled_reservations` field counts entries lacking a valid reported usage/cost receipt. These legacy display fields are **not** a global admission balance and do not establish completed-response proof. The new internal accountant independently retains usage-only historical holds. Do not sum the public reported cost and original reservations as though that were a bill, or expose global accounting as the current owner's spend.

## Executed offline proof

RED before changing accounting:

```text
go test -run '^TestDictationSettledTenReceiptsAdmitWithinUnchangedCap$' -count=1 .
FAIL: ten completed receipts costing 40404 microUSD must not exhaust $10
      speech application limit reached
```

GREEN after implementing bound settlement: the same test admits nine additional conservative holds, rejects another, and retains all nineteen entries. Its pure dry-run compares ten completed synthetic receipts with the same ten unproven legacy receipts without mutating either input. No live receipt contents are used.

Additional RED→GREEN checks caught conflicting legacy receipts, incomplete token breakdown rewriting, the obsolete 64 KiB read bound, and an oversized write that would have made the next read fail. Footer regressions additionally verify original field semantics and owner isolation after settlement.

Executed checks:

- `go test -race ./...` and `go vet ./...`: pass. Includes cross-process reserve/crash limits; hard process exit after receipt commit followed by concurrent exact receipt replay; racing settlement/admission; malformed/stale/duplicate evidence; integer cost validation; transport disconnect/incomplete/cancelled/missing usage/write failure; unchanged cap; and owner privacy.
- `node --test web/tests/*.test.mjs`: 174 tests, 173 passed, one opt-in skip, no failures. Node emitted its existing experimental localStorage warning.
- `swift test` in `native/Core`: 102 XCTest cases, four opt-in skips, no failures; 84 Swift Testing cases passed. This is CPU-only compatibility/regression evidence, not native policy-2 playback parity.
- `python3 native/ci/verify_dictation_policy_bridge.py`: all three actual Swift-to-Go handler tests passed, including lost start/progress acknowledgment followed by durable Stop and cold restart. No Simulator or provider involved.

## Release gates still open

1. Independent review of this integrated candidate, including settlement provenance, rate assumptions and persistence/rollback compatibility. This worker's own tests are not independent review.
2. Prove any historical receipt matches before proposing a migration; no actual production writes are authorized. The existing user's block remains unverified/unresolved.
3. Native policy-2 UI/transport parity remains disabled and unimplemented in this follow-up. No fallback to policy 1 was introduced. Simulator handoff is still required from the parent; the Coach slot was not touched.
4. Assessment integration remains another worker's scope. Keep the `dictation-manual-pacing.md` replay contract: server-accepted starts are not 100% completion, unreported offline playback remains unknown, and this is not a complete offline media-event outbox. Durable Stop recovery was not changed.
5. Do not roll back to a typed writer that drops `settlement`, owner attribution, pacing history, replay evidence or Stop receipts. Deployment and user-unblocked claims require the parent-coordinated release gates, not merely a local commit.
