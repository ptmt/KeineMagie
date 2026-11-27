# Durable Dictation attempts — image published, deployment pending

Base `63e8a16`, including operator recovery `67da4fb`. Scope is backend, web, tests, and documentation only; no native or unrelated UI candidate is included. All new test receipts are explicitly synthetic local WebSocket fixtures. Production rollout status is tracked separately below; local tests are not deployment evidence.

## Final verification and rollout gate

The final combined source passed `go test -count=1 ./...`, `go test -race -count=1 ./...`, `go vet ./...`, Node **199 passed / 1 opt-in skipped**, and all **40** injected SIGKILL windows. Independent re-review passed after four reproduced findings were fixed. Tracked evidence: `docs/dictation-prevention-evidence/verification.json` and adjacent real RED/GREEN outputs. The final receipt supersedes earlier test-stage documentation hashes; implementation hashes were checked unchanged throughout the final run.

Source `990040f0f70579aa15b31e600f9f8f07a5857cb1` was pushed non-force to main. Server CI **45997270178**, job **140499696340**, succeeded and published the verified ARM64 image `ghcr.io/ptmt/diktat-server@sha256:e19f11b6a44d4bd9516fd1cac25d6c3a60c5a936e1a36ef7146600d32d9dbffd`. A disposable keyless container using that registry image returned health 200, private Dictation/web session 401, source path 404; both changed web assets matched committed bytes with no-store. The disposable container had no production mounts and was removed/read-back absent. These were isolated local HTTP checks, not deployed public HTTPS checks. Details: `docs/dictation-prevention-evidence/publication.json`.

**Not deployed at this checkpoint.** The production read-only preflight tool request is awaiting command approval (two identical requests returned `pending_approval`, without execution). Do not replace the backend until the fresh idle/store/account/generation lock checks pass; do not infer current capacity from the earlier recovery snapshot. The prepared deployment runner preserves all fresh durable bytes, changes only the pinned CI backend image, keeps worker/config unchanged, and prohibits old-writer rollback. It does not release any historical holds or restore any data. Backend prevention will apply to both clients; native-specific feedback remains a separate unpublished candidate.

## Protocol boundary

Official OpenAI documentation was checked during this task: the Realtime [cost guide](https://developers.openai.com/api/docs/guides/voice-latency-cost) identifies response creation as the conversational billing boundary (connections/bandwidth currently uncharged); the [conversation guide](https://developers.openai.com/api/docs/guides/realtime-conversations) separates adding a text item from requesting inference with `response.create`. This application sends text only, disables turn detection, and enables no separately billed input transcription. Never-sent proof is specific to that transport; introducing VAD, transcription, or automatic responses requires a new admission-policy review. No prices or model policy were changed here.

## Persistence and admission contract

`generation.lock` remains the sole cross-process producer fence. An uncached owner/record/asset key is hashed independently of the login session and retained across months. Reservation IDs use random 128-bit IDs; duplicate IDs, response receipts, and active keys fail closed.

The additive monthly `attempt_policy: 1` and per-entry `attempt.version: 1` implement:

- `prepared`: the original $1 hold exists, but `response.create` has not been authorized. No new daily or owner quota is consumed.
- `attempted`: intent, UTC day, characters, and reserved seconds commit in **one monthly fsync/rename transaction**, immediately before the real transport sends `response.create`. This consumes one shared daily request and one owner daily request. Legacy daily counters and owner generations are included, never rewritten or reset by this path.
- `completed`: matching `response.created`/completed `response.done`, full validated usage, and bound settlement commit atomically. The original reservation and fields remain. Local transcript/audio validation and asset publication occur independently afterward.
- `released`: only a still-`prepared` attempt can receive durable `prepared-no-response-create-v1` proof. Its effective hold becomes zero; no provider cost or completion receipt is invented.

The next locked POST recovers proven prepared entries, including older months, after validating every ledger. Legacy entries without attempt proof are untouched. Unsupported policy versions, unknown fields (including nested evidence), malformed ledger shapes, and unfamiliar legacy daily counters reject paid admission without rewriting the originals. Cached GET/POST does not consume quota and remains usable even when accounting is unrecognized.

Monthly admission remains **10,000,000 microUSD**. Connection, configuration, context cancellation before intent, and monthly refusal consume no new daily allowance. A prepared request that crosses a month boundary cannot send; it is released and can be prepared again. Once attempted, its identity remains blocked across months even if its audio was never published.

The transport persists completed usage at the first validated matching `response.done`, before checking local narration or publication. Bounded malformed/missing audio can therefore fail publication while the completed receipt settles correctly. Cancellation after receipt parsing does not erase that evidence. Identity is revalidated at attempted admission and publication; logout after a receipt preserves settlement and returns 401.

## Conservative cases and rollback

There is necessarily a durable-intent/send gap. Death, cancellation, or I/O uncertainty after intent commit but before the actual send can retain a full hold and daily quota even if the provider received nothing. An attempted disconnect, partial/error/cancelled result, missing/unbound/invalid receipt, or failed receipt write remains uncertain. Neither age nor a repeated POST refunds it or sends another paid request. Completed-but-unpublished assets also cannot regenerate automatically. Resolving these cases requires separate trustworthy evidence and an authorized recovery procedure; this change does not solve every ambiguous billing outcome.

First and repeated failures expose `speech_recovery_needed`, `recovery_needed`, and the scoped reason `attempt_outcome_uncertain` or `completed_audio_unavailable`. No global/other-owner spend, receipt IDs, or provider prose is exposed. Web feedback preserves the draft and blocks repeated preparation locally; the durable backend remains authoritative after reload.

The ten November legacy recovery-adjusted entries must remain owner-unknown and keep their originals, recovery digests, and $0.80 unknown-cost reserve each. A synthetic ten-entry preservation test verifies the same $8 accounting after a new-policy write/release. No historical completion proof was manufactured. Legacy receipt-display semantics remain intact. For new attempts, proven releases no longer appear pending; attempted entries with partial usage still appear unsettled. Original reservation audit totals remain unchanged and are not the effective admission balance.

**Rollback is policy-aware only.** Once a store has `attempt_policy: 1`, do not run an older binary/operator writer that ignores or strips attempt, policy, settlement, or recovery fields. Do not mix old and new producer versions. Preserve all monthly files and the legacy daily/owner files; do not delete attempt history to unblock an asset. A future rollback writer must understand this policy or refuse the store. There is no destructive downgrade/migration command in this candidate.

## Executed TDD evidence

Raw command output is in `scratch/dictation-prevention/`. An interrupted command applied the initial candidate; after listeners were enabled, production files were restored to HEAD for the real-transport RED run, then the candidate was reapplied. The blocked listener attempt (`01`) and preliminary green (`04`) are retained but are not claimed as baseline RED evidence.

| Regression | Actual RED | GREEN |
| --- | --- | --- |
| Never-sent failures exhaust daily allowance | `02-red-never-sent.log` | `03-green-never-sent.log` (completed despite tool interruption), `07`, and final suite |
| Completed receipt with wrong narration/no audio retains $1 instead of synthetic 406 microUSD | `05-red-real-transport-baseline.log` | `07-green-targeted.log` |
| Malformed audio discards receipt; cancellation after receipt publishes audio | `08-red-wire-lifecycle.log` | `09-green-wire-lifecycle.log` |
| Locked admission fails to recover prepared holds when configuration is missing | `12-red-recovery-admission.log` | `13-green-admission.log` |
| Recovery mistaken for draft conflict; first failure lacks status | `14`, `15` | `18`, `19` (`16` retains an intermediate test assertion failure) |
| Logout/cancellation before intent consumes allowance | `24`, `26` | `25`, `27` |
| Cached POST blocked by unrecognized accounting | `29` | `30` |
| Null/missing ledger shapes or unknown legacy daily schema admit generation | `31`, `33` | `32`, `34` |
| Logout after receipt loses 401 status | `35` | `36` |

Subprocess tests hard-exit before/after attempted-intent commit and before/after receipt commit through the production WebSocket transport. They reacquire the producer lock, verify durable state/charge, and prove safe release versus blocked retry. An additional local overlay harness SIGKILLs a producer holding `generation.lock` at all 40 combinations of prepare/intent/receipt/release and before/after write, file sync, close, rename, and directory sync. It executes a generated instrumented copy of the actual atomic writer without adding production fault hooks (`43-sigkill-producer-locked.log`, detailed `scratch/a/sigkill-windows.log`). These process-kill tests do not emulate physical power loss inside filesystem fsync. Tests also cover concurrent HTTP producers, duplicate evidence, owner isolation, rollover, legacy quota inclusion, recovery override preservation, real local handshake/dial failures, canceled/partial/error/completed wire results, and cache replay. No historical/live receipts are reconstructed.

Before independent review, combined checks passed: `go test ./...` (`44`, 114.249s), `go test -race ./...` (`45`, 139.145s), `go vet ./...` (`46`), and `node --test web/tests/*.test.mjs` (`47`: 198 passed, one opt-in skip, zero failures). The 40 SIGKILL windows passed (`43`); added spend tests passed (`41`). The earlier race run (`21`) failed three existing Unix-socket tests because the long scratch path exceeded macOS's socket-path limit; the final runs use the shorter worktree-local `scratch/t` and pass without skipping them. Paid acceptance was explicitly disabled. `verification.json` records those commands, outcomes, and tested source hashes. `git diff --check` passed; HEAD remains `63e8a16`.

## Independent review fixes — local verification

All four reproduced review findings have actual RED then GREEN regressions. New evidence is isolated in `scratch/dictation-review-fixes-20261127/`; the earlier logs and manifest remain intact.

| Finding | Fix and exercised regression |
| --- | --- |
| Case aliases bypass persisted usage validation | The default ledger decoder checks exact canonical keys, duplicate keys, and unknown fields recursively before any permissive provider decoder. Eight alias/duplicate cases refuse the production transaction and preserve the original bytes. |
| `Glob` hides unreadable directory errors | `os.ReadDir` errors propagate before mutations. A real `chmod 0300` fixture under `generation.lock` proves no duplicate active key is created and subsequent recovery remains usable. |
| Prepared holds leave no room for release/completion | Preparation and dispatch reserve serialized headroom for every pending attempt's release or completed settlement, including maximum bounded usage and JSON escaping of a 256-byte response ID. Padded legacy-ID fixtures reject unsafe admission without changing originals at 10, 100, and 1700 remaining bytes; admitted fixtures successfully release, recover, and settle. |
| A late recovery rejection blocks a switched owner | `blockedAudio` mutations require the captured owner and identity epoch. The mounted controller delivers A's rejection after switching to B, then executes B's preparation for the same record/asset. |

`01-red-go.log` records failures for the first three findings; `02-red-node.log` records the executed owner-switch failure. Their focused GREEN runs are `03-green-go.log` and `04-green-node.log`. Final focused `go test -race -count=1 -v -run ... ./...` passed 41 top-level tests (127 including subtests), with the private-snapshot operator test skipped (`05-focused-go-race.log`). `go vet ./...` passed (`06-go-vet.log`). The full Node suite passed 199 tests, with one opt-in skip (`07-node-all.log`). `verification.json` records exact commands and source/log hashes; Go fixtures use worktree-local `scratch/t`.

The $10 cap, legacy operator recovery evidence, and uncertain-attempt retry policy remain unchanged. No TTL refunds or new paid retries were added. These are local synthetic/filesystem checks, with paid acceptance disabled; the earlier process-kill evidence does not establish power-loss durability or actual provider billing. No commit, push, deployment, or production access was performed.


## Changed files

- Backend lifecycle/schema: `server/dictation_attempt.go`, `dictation_ledger_json.go`, `dictation_monthly.go`, `dictation_settlement.go`.
- Production admission/transport and feedback: `server/dictation_audio.go`, `dictation_openai.go`, `dictation.go`, `dictation_spend.go`; legacy helper comment in `dictation_budget.go`.
- Backend tests: new `server/dictation_attempt_test.go`, `dictation_attempt_transport_test.go`, `dictation_attempt_crash_test.go`, and the additional local `dictation_attempt_spend_test.go`; extended `dictation_settlement_transport_test.go` and adapted `dictation_paid_http_test.go` to invoke the durable send boundary.
- Independent review regressions: `server/dictation_review_regression_test.go` and the mounted owner-switch case in `web/tests/dictation-budget.test.mjs`.
- Crash harness: `scripts/test_dictation_atomic_windows.py`, `scripts/fixtures/dictation_atomic_windows_test.go`. Its default scratch directory is inside this worktree.
- Web: `web/dictation.mjs`, `dictation-i18n.mjs`, `tests/dictation-budget.test.mjs`.
- Documentation: this file and a supersession note in `docs/dictation-budget-settlement.md`. No native or unrelated feedback-commit files were imported.
