# Authorized stale Dictation hold recovery — APPLIED

## Verified production outcome — 27 November 2026

The explicitly authorized conservative recovery is **applied**, with independent locked readback completed at **11:08:50 UTC**. All ten original $1 reservations, reported usage/costs, absent owner attribution and absent settlements remain intact. Additive hash-bound `operator_recovery` metadata retains **$8 unknown-cost reserve**, releases **$2 admission capacity**, and keeps the monthly application cap **$10**. This is an operator risk allocation, **not** a provider invoice, final-cost claim or fabricated completion proof.

Actual deployed-source HTTP admission on locked copies of the live monthly ledger, daily ledger and owner history admits the first two preparations, rejects a third uncertain attempt, and preserves the daily and owner rejection gates. The provider seam returns a deliberate error before transport. **No paid generation or real signed-in provider operation was exercised.** Available capacity is a verification-time snapshot, not a promise after subsequent owner activity.

## Source and actual deployment

- Original isolated implementation: `091d23b9e75c4cf80e9e1b9023204043b544c99f`, based on previous live source `046099dfa71f8b1880b2fd8b3575ab47c7246efe`.
- Rebased onto current main, preserving intervening native commits without changing server/web/workflow content: **`67da4fb3b883a0a61b890fa1e823775abb7ce5ac`**. Only the five recovery accounting/test files changed relative to main. Pushed and remote SHA independently read back.
- Normal GitHub server CI **45987192838**, build job **140465725867**, exact source: **success**, including image publication. No TestFlight upload was requested.
- Pulled and deployed registry ARM64 image **`sha256:ab9d4cbd46a90617b12d71e10840eae479202e791371312e22cf85c4e263ffef`**, `ghcr.io/ptmt/diktat-server:sha-67da4fb`; OCI revision equals source above.
- Running backend container **`b75a74024f47c302a9e1c7612533398772d71feed0a61643b55dd693b76d3736`**; `/app/server` SHA-256 **`6e49ed42a63c1b7a6547886f0d698ee183a85b327a7c198c2391d5307939f293`**.
- The earlier local image `192d8de20656…` was **not deployed**. Existing original Compose base + durable `compose.translator.yml` lifecycle was used, backend-only `up -d --no-deps --pull never`, not a new manual container launch or automatic tinyserve deploy.

## Locks, preservation and recovery

Nonblocking host release, engine, durable-store and account-active locks were acquired before idle checks and stopping only the backend. The lifetime podcast runner flock was acquired after stopping. Fresh snapshots matched the exact hash-bound source ledger; private durable backup preceded the atomic ledger replacement. The runner lock was released immediately before the policy-aware backend startup; other locks remained through durable-data and configuration comparison.

The **only changed durable file** was `dictations/paid-months/2026-11.json`; **all other 16 Dictation files and all other 65 nonruntime volume files** remained byte-identical. Worker and every unrelated container ID, full merged configuration except backend image, secret values, resources, mounts, networks and routing labels were compared and preserved. No original-worktree, AnyProgress, profile, native or web UI changes were deployed.

The old field-dropping binary's restart policy was explicitly disabled before stopping/migration; Compose removed/replaced that container. Old override is forensic-only. Forward recovery is pinned to the policy-aware registry image. **Never restart the old binary over recovered data, restore historical data, or rerun the one-shot apply script.** Use the original base and the backup's `compose.policy-safe-recovery.yml` for backend-only lifecycle operations, or a reviewed preservation-safe forward fix.

## Receipts

Private durable evidence directory (0700; evidence files 0600):

`/Users/tinyserve/Library/Application Support/tinyserve/services/keinemagie/deployment/dictation-recovery-20261127T110605Z/`

- **`verified.json`**: completed deployment, preservation, HTTP and copied-handler admission receipt.
- `keinemagie-data.tar`, `month.live.before.json`, `month.live.after.json`, `data.before.json`, `data.after.json`, `data.reverified.json`: immutable historical backup/readback evidence; not restoration instructions.
- `containers.before.json`, `containers.after.json`, `containers.reverified.json`, private merged config snapshots; never publish these secret-bearing files.
- `apply_recovery_reviewed.py`, `verify_applied.py`, `operator_live_copy_test.go`, `live-copy-admission.log`, `compose.policy-safe-recovery.yml`.
- Ledger before SHA-256 **`c01aee58778bee3e51f34869cdea71831d703c3621463f2a52ec647b090ededc`**.
- Ledger after SHA-256 **`ca8a8cb822151c9e38d667c3ee434edbd9e8e369547214fc3763bdb7f4b4805b`**.
- Admission log SHA-256 **`c61e99e524b459180ad5c504ee108f3d26b877befd81bc91b2c6f821e6ff6459`**.

## Verification and issues

`go test -race -run TestDictation -count=1 .`, opt-in private snapshot accounting/admission/settlement tests and `go vet ./...` passed. A clean archive of the exact deployed SHA plus the external copy-only test passed `TestOperatorLiveCopyAdmission`: real handler, live limits and live counters, synthetic identity and no provider send. Historical records remained unchanged after copied prospective attempts. Invalid policy/digest/reserve/month/owner/settlement inputs fail closed.

Certificate-validated public `https://keinemagie.tinyserve.org/health` returned **200**; `/v1/learning/dictations` and `/v1/web/session` returned **401** without credentials. First immediate post-start health verification was non-200; a later protected check timed out while verification itself retained store locks. Release locks after final data comparison **before** public API probes. Independent final read-only verification succeeded; no rollback or repeated ledger apply occurred. Initial `INCOMPLETE.txt`/stderr remain historical evidence, superseded by completed `verified.json`.

The original scratch `deploy.py` remains obsolete and unsafe: **DO NOT RUN**. Normal approved tools worked on this retry; no guard bypass was used. Actual provider speech quality/generation remains untested and requires a deliberate authorized user operation.
