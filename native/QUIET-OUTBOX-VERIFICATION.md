# Quiet translator candidate — not published

Base: fresh origin/main 5b871f109034c31eaa6dd0a0d919f8bda5780305 (compact Coach 03599b0). Isolated worktree `/Users/tinyserve/Projects/KeineMagie-translator-quiet`, branch `candidate/translator-quiet`. Original dirty Diktat worktree and separate OpenAI TTS work untouched. No provider inference, credentials, push, deployment or Apple upload.

## Behavior

Main screen has composer → Translate → result/history. Unresolved work appears as one gray tappable line, with count only for multiple requests. No queue heading, explainer, completed queue rows, Retry/check combination, or visible Delete/Cancel buttons. Native pending sheet contains only unresolved requests; secondary actions are in its ellipsis menu. Five locales have short plain labels; Russian error is “Не удалось получить ответ”. Accessibility text sizes use a full-height sheet.

Storage/enqueue/idempotency rules are unchanged. Completed/cancelled receipts are filtered for presentation, not purged. Distinct same-text receipt IDs remain distinct. Explicit safe-preflight retries reuse their original snapshot/key. Unknown outcome and server-error recovery use GET history only and never POST. Missing answers remain unresolved. There is deliberately no new-generation retry button for unknown requests; checking cannot silently spend. Existing cancellation/deletion semantics remain secondary.

Actual deployed contract inspected: `server/account_translation.go` authenticates owner and GET returns owner's history before provider access/admission; `translation_outbox.go` derives record ID as `outbox-` + SHA256(owner + NUL + exact request-key). Native checks use that identity, never source text. A POST with missing receipt could infer, hence relabeling Retry as Check would have been unsafe. No backend endpoint/change is needed. Added server contract assertions for stable identity, invalid-session rejection, other-owner isolation, and zero GET provider calls.

## Verification

- Actual AppModel harness: 45 Swift Testing tests pass, including lookup-only, coalescing/owner-reset late-read fences, durable same-text distinct receipts, draft preservation, original keys, automatic preflight recovery, auth invalidation, cache and provider advisory behavior. Recorded RED for POST-on-check and stale per-owner notices, then GREEN.
- Core: 17 XCTest + 68 Swift Testing pass.
- Native CI: 50 tests, 1 skip, no failures (`quiet-ci-final.log`).
- Server `go test ./...` passes. Added exact lookup contract test separately passes after final edit.
- Release iPhone 18 Pro / iOS 27.2 isolated simulator `9677A05F-6E50-4494-9C0E-3B9CA0915FB4`: 6 quiet UI tests pass; 5 outbox/catalog regression tests pass; 2 dark/accessibility tests pass. RED was observed for missing compact summary and for clipped large-type recovery action, then fixed and rerun.
- UI states: empty; typing with keyboard; translating; completed; long result; five localized failed screens; two pending items main/sheet; background/foreground and real terminate/relaunch; dark and largest accessibility size. Final history copy rectangle is above floating tab bar. Medium sheet at accessibility size clipped the action: fixed with large-only detent and screenshots re-inspected.
- Reduce Motion preference was enabled and read back as 1 for final/dark runs; no application-side UIAccessibility runtime probe was added, so this is preference-level evidence, not an independent runtime assertion.
- Existing horizontal style strip scrolls/clips its next item at maximum Dynamic Type; unrelated to outbox, unchanged. Main history can naturally scroll beneath translucent tabs, but final control is proven reachable above them.

Results: `/Users/tinyserve/.hermes/cache/scratch/quiet-translator-final.xcresult` (6), `quiet-translator-regression.xcresult` (5), `quiet-translator-dark3.xcresult` (2). One earlier combined UI run timed out amid concurrent simulator work; reran bounded suites serially and all passed.

## Parent visual review

Screenshots are synthetic transport fixtures, not live provider output, exported to `/Users/tinyserve/.hermes/cache/documents/translator-quiet-review/`:

- `light-quiet-empty.png`, `light-quiet-typing-keyboard.png`
- `light-quiet-translating.png`, `light-quiet-completed.png`
- `light-quiet-completed-history-bottom.png`, `light-quiet-completed-long-output.png`
- `light-quiet-failed-{de,en,ru,es,fr}.png`
- `light-quiet-unknown-sheet.png`
- `light-quiet-two-pending-main.png`, `light-quiet-two-pending-sheet.png`, `light-quiet-relaunch.png`
- `light-quiet-dynamic-type-sheet.png` (final corrected sheet)
- `dark-quiet-unknown-main.png`, `dark-quiet-unknown-sheet.png`, `dark-quiet-dynamic-type-sheet.png`

No publication until parent reviews actual screenshots. Flame artwork, Coach, read-only cache and provider advisory behavior were not modified.

## Independent review follow-up (local only)

Reviewed candidate `85b4455e67295920067b6e61aa60dbe978d6dbeb` against its parent and inspected the synthetic Russian main/error, light/dark recovery sheets and corrected accessibility-size sheet. The main screen is accepted as reasonably compact; no language warnings, new main-screen actions or redesign were added.

Found and fixed with failing tests first:

- Hidden completed receipts counted toward the 200-item admission limit, permanently blocking translation with no reachable cleanup. The limit now applies to unresolved work; completed/cancelled receipts remain stored. Tested 201st lifetime submission, full unresolved capacity and duplicate coalescing at capacity.
- An in-flight request could be locally cancelled/deleted and the same draft submitted under a new key while the original request was still running. Sending rows now have no removal menu, and AppModel refuses removal until delivery settles. Queued actions say “Stop waiting”; removal says “Delete from device”, not server cancellation. Empty sheet says “No pending translations”, not a false claim that deleted requests have answers.
- Provider-preflight failures lost their original-request retry route: connecting alone never requeued failed work. The pending sheet again exposes Send again with the same immutable key alongside connection settings.
- Sheet presentation discarded active composer focus. Dismissal restores focus only if the editor was focused before presentation; Release UI test proves unchanged draft, visible keyboard and continued typing without retapping.
- A cancelled lookup accepted an uncancellable late response; local cancellation could also acquire a late failure notice. Lookup completion/failure now checks task cancellation, signed-in state, owner/generation/epoch and the still-unresolved item. 401 still invalidates the authenticated owner.

Expanded actual-AppModel tests reject same-text wrong IDs and same request UUID hashed under another owner, prove exact-ID success, original POST-key reuse, lookup-only server-error handling, persisted recovered history through a fresh cache instance, an older empty history refresh arriving after recovery, late owner replacement with a real matching response, local cancellation and cancelled lookup tasks. Gate responses are captured before suspension; test caches are isolated under each fixture root.

Fresh verification after fixes:

- Actual AppModel: 52 Swift Testing tests pass.
- Core: 17 XCTest + 68 Swift Testing pass.
- Native CI: 50 tests, one existing skip, no failures.
- Server: `go test ./...` passes from `server/`; owner/authenticated GET contract and zero-provider assertions included.
- Release: 14 tests pass (9 quiet + 3 outbox + 2 catalog), no skips, isolated iPhone 18 Pro / iOS 27.2. Result: `/Users/tinyserve/.hermes/cache/scratch/quiet-review-release.xcresult`; attachments: `quiet-review-release-shots/` beside it. Earlier RED results remain as `quiet-review-ui-red.xcresult` and `quiet-review-provider-red.xcresult`.
- Prior dark two-test evidence remains applicable; inspected dark sheet, and reran largest accessibility-size sheet in the final Release suite. No VoiceOver runtime claim.
- Added-line security pattern scan and `git diff --check` clean. Existing Xcode UI-test actor warnings also occur in the candidate baseline; result bundles, rather than incidental compiler wrapper diagnostics, establish test success.

No real paid inference, credential access, push, release, deployment or Apple upload. Other worktrees and parallel candidates were not modified. Parent must merge and run combined verification before publication.
