# Podcast quota diagnosis and authorized reset — 2026-11-11

## Confirmed live cause

Read authoritative `/app/data/podcasts/jobs.json` from the running backend using `docker cp` into memory, validating `jobs` array and `budgets` object. Backend image `sha256:7f037ed2956a3199cd701751b6e29a4795e0384ccf503f5cf762dbe0648818fa`, started `2026-11-11T09:37:15.764512335Z`.

Before reset: **0 jobs, 0 active, 1 subscription, 4/4 admissions on 2026-11-11 UTC**. Thus the exhausted gate was daily podcast admission, NOT two-active concurrency, retained storage, audio size, or translation quota. Personal translation file held **6 attempts dated 2026-11-10**, against configured 100/day; effective current-day usage zero. Aggregate admission storage has no per-admission ledger, so historical duplicate/failure attribution cannot be proved from this snapshot. Prior idempotency already coalesces concurrent retained imports before charging; deleted jobs intentionally leave daily admissions consumed.

Publisher check: first saved enclosure uses supported `awCollectionId`, `awEpisodeId`, `v` parameters. Bounded IPv4 HEAD followed one 302 to 200 `audio/mpeg`, content-length **79,346,779**, below **314,572,800** byte ceiling. This is current host reachability, not a full production fetch/recognition/translation or proof about every feed episode.

## Authorized live operation

User explicitly requested resetting their test quota. Exactly one auth user; all persisted sessions and the subscription belonged to that same user; its derived hash matched the sole podcast budget. No account identifiers or credentials exported.

Private backup directory: `/Users/tinyserve/Library/Application Support/tinyserve/services/keinemagie/deployment/quota-reset-20261111T102636Z` (0700; both before snapshots 0600).

A network-disabled ephemeral worker-image Python process held auth sidecar, translation `.active` and `.lock`, and podcast `.lock` flocks nonblocking. Revalidated zero jobs before modification. Reset only the authenticated owner's current-day podcast admission attempts **4 → 0**, using same-directory temp file, preserved UID/GID, 0600, fsync, rename, directory fsync. Translation quota was not exhausted and was not changed. Subscription, jobs, credentials, history, limits configuration and all other data preserved. No queue cancellation/deletion, inference, restart, commit, push or deployment.

Independent Docker readback: **0 jobs, 1 subscription, 0 current-day podcast attempts**. Public certificate-validating `curl -4 /health`: **200**, `status:ok`, at `2026-11-11T10:27:04Z`. Python's default route returned 403; IPv4 curl succeeded.

## Reviewed release candidate (not deployed)

- Typed owner-active, owner-retained, global-active, global-storage and daily-admission errors, retaining string `error` for native compatibility and sentinel compatibility via `errors.Is`.
- Structured `code`, `limit`, `remaining`, owner-only `limits`; daily `retry_after` and `Retry-After` until UTC midnight.
- Existing authenticated podcast GET adds owner-only quota counters/reset time from the same locked snapshot as jobs; no owner IDs/global usage. Independent review caught the original two-snapshot inconsistency; concurrent regression now covers it.
- Under store lock, quota eligibility now precedes worker readiness, after retained-identity lookup. Rejected/unavailable admissions and repeated retained imports do not consume budget. No limits lifted and no speculative automatic refunds.
- Tests demonstrated both original missing daily reason and needless readiness probe red before fix; GET status test also demonstrated red.
- Final `go test -race -json ./...`: **306 test/subtest passes, 4 opt-in skips**. `go vet ./...` and `git diff --check` passed. Evidence `/Users/tinyserve/.hermes/cache/scratch/km-session-quota-race.json`. All source ceilings in `podcast_limits.go` remain byte-identical to HEAD: **10800 seconds / 314572800 bytes**.
- Web retains structured reason, remaining, retry interval and owner limits; distinguishes daily admissions from concurrency, storage, global capacity and personal translation quota. All **46 Node tests** pass. Synthetic browser checks: session **11**, guest **23**, directions **19**, styles **13**, podcasts **41** (real HTTP artwork fixture, no artwork skip).
- Web-session identity now returns only locally verified user, cookie-bound CSRF and expiry; no provider/catalog call. Unavailable/blocked-provider Go regression showed red first and now passes with zero catalog calls. Provider status is independently fetched on account/translator, never required for podcast identity or history completion. 401 clears private content and stale responses cannot restore it.
- Latest UI request included: direction immediately above textarea grid; compact unboxed style text below first input only; no whole-panel route-focus ring, while keyboard Tab keeps a visible 3px interactive-control ring.
- Independent final read-only review: **No blockers** (`km-quota-review-final.txt`). A first CLI attempt failed on unsupported configured model; retry with cached supported review model completed.

## Live readback and deployment hold

Independent Docker readback from the source-derived `/app/data/podcasts/jobs.json` first confirmed **0 current-day admissions / 0 jobs / 1 subscription**, with exactly one auth owner and both sessions plus all subscriptions belonging to that owner. No second reset was performed.

The user subsequently started actual work. At **2026-11-11T10:56:45Z**, live storage contained **1 job, state transcribing; 1 subscription; 1 current-day admission**. Thus the reset held and a new admission was accepted. Public certificate-validating IPv4 `/health` returned **200**. This is not proof of translation completion.

Built candidate Linux arm64 image: `sha256:812286007ede7c8ce0d2c0fde2f4f9e00cf2e9ba6e256b6490c27c422f4ad8b8`, using the repository Dockerfile with network-disabled build steps. **Deployment is deferred to avoid interrupting active real recognition.** Production remains backend `7f037ed2956a…`, worker `44b2fccc4df1…`; no override edits, restart, cancellation, seed data, paid inference or auth bypass. Do not claim the new JS/session handler is live until a safe backend-only rollout and exact public bytes/image readback have completed.

New imports intentionally consume one daily admission once durably queued even if subsequent fetch/recognition fails; no claim of success-only billing. Daily podcast quota resets by UTC date, independently of the personal translation budget. No automatic refunds or limit increases were added.
