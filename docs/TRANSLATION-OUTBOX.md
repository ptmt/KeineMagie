# Translation drafts and outbox — isolated candidate

## Scope and release status

Candidate worktree: `/Users/tinyserve/Projects/KeineMagie-outbox`, branch `candidate/translation-outbox`, based on `df309d4`. The original `/Users/tinyserve/Projects/KeineMagie` working tree, including unreleased Diktat, was not copied, staged, or modified. No push, deployment, TestFlight upload, real credentials, or provider inference. Server must ship before this native candidate: old servers ignore idempotency/expected-owner headers and cannot provide these guarantees.

## Reproduced root causes

Actual AppModel harness, before fix: held `/v1/auth/session` and stale `recordNetworkFailure` both produced **zero translation POSTs**, despite a functioning translation transport. `SessionController.canWrite` combined identity, online verification, reachability and `checking`; AppModel and submit UI used it as a preflight gate. Submit additionally required successful provider catalog/model readiness. Composer text was only RAM.

A second actual Go regression held the provider status catalog response and proved a same-owner translation could not start within one second: advisory status held the credential owner lock across network I/O. The fixed status releases that lock before catalog I/O and does not refresh credentials. Explicit idempotent translation directly requests the existing preferred personal model (`gpt-6-luna`), without model-catalog preflight or any shared-key fallback. Legacy non-idempotent client model selection remains unchanged. An unavailable model is a real translation error, not guessed connectivity.

Evidence: scratch `outbox-red.log`, `outbox-core-red.log`, `outbox-app-red.log`; Go tests include the held-catalog regression. Synthetic requests only.

## Local contract

- Composer changes are saved synchronously as atomic protected JSON, owner-only permissions, excluded from backup. Scope is exact server origin plus trusted SessionController owner; filenames are hashed. The synchronous MainActor operation is the local lease: validate scope/generation and write without suspension.
- Unknown identity uses a separate unassigned namespace. It is never automatically adopted by a login, and cannot send. Login screen permits local editing/copy. Copy before signing in to explicitly transfer text; no cross-account adoption UI is included.
- Translate first persists an immutable UUID/text/direction/resolved-style snapshot. Only then may it POST with bearer, `Idempotency-Key`, and `X-Translation-Owner`. Text including Unicode and whitespace is preserved. An auxiliary check does not gate this explicit request; server authentication remains authoritative.
- Pending work belongs to AppModel, not the view. Rapid identical pending taps coalesce; different submitted items drain serially. Typing without tapping never creates AI work. Completion does not replace the current draft. Snapshot style and selected composing style survive relaunch.
- States: queued, sending, failed, completed, cancelled, needsDecision. Retry uses the same key/snapshot. Cancel/delete stop future local attempts and ignore late completion; they cannot recall an already delivered provider request. Server history may consequently contain a cancelled locally completed request.
- Foreground-only auto-send requires same-owner online identity validation in this process. Later advisory failures do not revoke it; 401/logout do. A cold prior-owner proof allows explicit authenticated attempts while validation is pending, but does not itself grant automatic sending.
- Auto-retry only for known pre-delivery connectivity errors, at most three total attempts, 5/10-second backoff checked by a foreground 3-second poll. Timeouts/lost connections and restored `sending` require a manual result check. No iOS background/terminated-delivery guarantee.
- Storage failure blocks new sends and is visible. Corrupt loading fails closed without overwriting the old file. Queue limit: 200 retained items; users can delete completed/cancelled items. Every keystroke currently rewrites the bounded journal; large histories may warrant a separate composer file after measured device profiling.
- Explicit logout/server switch purges current owner's draft/outbox. A deny-only preference prevents a residual old file from being restored after failed deletion; it never establishes identity. 401 hides content and invalidates trusted proof; failed item remains scoped for a later same-account sign-in. A different account cannot view/send it.

## Server contract

Authenticated owner is resolved before receipt lookup. An expected-owner mismatch is 403, never reassigned. Optional headers preserve old client compatibility. Request body and key are bounded/validated. Same owner/key with changed payload is 409.

Durable receipt claim precedes quota/provider work under a sidecar flock. Completed retries return the same record without another provider attempt, quota charge, or history append. Pending receipts survive restart and yield 409; a crashed external call is **not exactly-once inference** and is never blindly re-spent. Pre-provider failures abandon their claim; successful quota admission occurs before marking provider started. Quota's existing cross-process account lock remains shared with podcast work.

History is saved before completed receipt. A deterministic owner+request history ID lets a pending replay recover that exact record (also checking its payload digest) and finish the receipt without spending again. A crash before durable history still requires manual decision. A replay does not resurrect deleted history. Receipt files are retained indefinitely in this candidate; retention/administrative cleanup needs a separate design that must not silently permit replay of expired keys.

Native error presentation distinguishes unreachable, authentication, provider reconnect (424 for new-header calls; legacy 503 unchanged), quota 429, server error, and uncertain outcome. 401 returns to native sign-in with an editable unassigned composer. No generic offline banner is inferred from a status endpoint failure.

## Verification

- Actual AppModel transport harness: 39 tests passed (held validation, stale offline, exact durable typing, duplicate tap, serial snapshots, continued editing, cancel/late completion, owner replacement, 401, disk failure, offline restore/manual retry, timeout/no auto-spend, advisory failure auto-recovery).
- Swift Core: 67 Swift Testing tests passed; XCTest suite also passed (see scratch `outbox-core-final.log`). Includes durable exact Unicode snapshot, sending recovery, scope separation, and logout residual-file denial.
- Python native CI: 45 tests, one existing skip, passed (`outbox-ci-close.log`).
- Full Go race suite and vet passed (`outbox-go-close.log`). Idempotency fixture proves one provider call/quota/history entry on lost-ack/restart replay; conflict/owner mismatch; history-before-receipt crash reconciliation and deleted-receipt conflict protection; interrupted completion and pending-crash rejection; status lock independence.
- Real **Release** simulator UI: both `TranslationOutboxUITests` passed in `outbox-ui-close.xcresult` (also `outbox-ui-final.xcresult` and `outbox-ui2.xcresult`): typing/keyboard and successful translation during held verification/catalog; queue and ongoing typing persist through real terminate/relaunch; different account gets no queue; same account retry completes without overwriting composer. Simulator uses UUID-namespaced storage and synthetic transport, not Keychain/provider accounts.
- App: scratch `outbox-release/Build/Products/Release-iphonesimulator/KeineMagie.app`, built with `CODE_SIGNING_ALLOWED=NO` (unsigned simulator artifact, not distributable). Exported screenshots: `outbox-ui-shots/`. Queue controls and status inspected. Existing floating tab bar overlays scrollable content near the bottom; no physical-device or comprehensive accessibility/layout certification.
- First UI run exposed a test assumption about cursor placement: tapping the editor moved insertion to the start. Test now compares actual exact edited text through relaunch, not an assumed appended string.

## Independent review

Fresh `codex-auto-review` source review finished with boolean `passed: true`, no security concerns or logic errors: `/Users/tinyserve/.hermes/cache/scratch/outbox-review-last.json`. Earlier findings led to quota-admission claim cleanup, history/receipt reconciliation (including missing receipt and changed-payload conflict), explicit logout after 401 purge-target handling, and deleted-history replay rejection. The reviewer did not run tests; host test evidence above is separate. Nonblocking suggestions: report abandoned-receipt cleanup failures more explicitly and reconcile later history metadata on replay. The default Codex model initially failed as unsupported; review succeeded using the locally advertised review model.

## Remaining acceptance boundaries

No physical iPhone/TestFlight validation. No real provider/model-availability assertion. Crash tests use persisted pending state/new handler, not server OS SIGKILL. App relaunch was exercised, but arbitrary power-loss/fsync durability on iOS is not claimed by atomic rename. Cancel cannot cancel server inference. A crash before durable history has the documented conservative ambiguity window. Unknown drafts require explicit copy rather than account adoption. No web UI expansion. Independent review verdict and final commit are reported separately; release remains unauthorized.
