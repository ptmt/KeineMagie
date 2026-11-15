# Coach chat iteration — candidate, not released

## Scope and baseline

- Isolated worktree: `/Users/tinyserve/Projects/KeineMagie-coach-chat-iteration`, branch `coach-chat-iteration`.
- Fresh `git fetch origin main` verified `origin/main` and candidate HEAD at `1c917c9e1ef2af116fd6b561acb649054846d3e1` before edits.
- No commit, push, deployment, TestFlight upload, production account mutation, real inference, credential-store/cookie access, or changes to the original dirty main/Diktat/TTS worktrees.
- User screenshot inspected with vision. Existing exact `gpt-6.1-terra` generation/assessment and failure separation are retained; no answer-list grading added.

## Implemented

Both web and iOS use compact single-surface exercise bubbles; stable turn IDs remain. Previous answered turns hide literal answer, correction and explanation once no longer latest. Latest feedback stays visible. Explicit answer reveal persists per owner/turn on the server; this is UI spoiler privacy, **not encryption or protection from inspecting a received payload**.

`POST /v1/learning/coach` adds `entry` and `seen`, and `reveal.text` distinguishes `source`/`answer` (empty retains legacy source behavior). Existing owner validation, browser CSRF and auth-revocation-serialized atomic writes apply. Source reveals before submission set server-computed assistance; post-answer reveals do not retroactively change original assistance. Each explicit disclosure stores type, exercise/turn ID, time and cumulative count in a private owner log capped at 512 entries; aggregate per-turn counts persist. No text/answers/source content enter that log. Existing action receipt limits still apply.

Read state is durable per message revision in the owner's single Coach conversation (`seen_version`, `message_version`). Clients explicitly acknowledge only active, visible messages near the conversation bottom; fetching is not reading. Older revisions cannot acknowledge newer feedback. The server cannot independently prove viewport visibility; this is a client receipt, not a security assertion. New-message accents and jump actions are present, scroll position is preserved while reading earlier turns, and near-bottom arrivals follow the conversation. No polling or background inference added.

The localized `30 секунд`/30-second composer chip sends the existing bounded practice request immediately, coalesces rapid taps and does not overwrite the draft. Header Practice/Refresh controls are removed; web touch pull and native refresh remain. Existing Profile entry is available. Native rechecks use a quiet ellipsis menu; web failed/retryable assessments use a disclosure rather than an action beside each verdict. Web dark-mode text inheritance was fixed after inspecting actual screenshots.

### Five-hour default

Entry creates a **templated free greeting/offer**, e.g. `Есть 30 секунд?`, not an AI-generated exercise. Only explicit practice sends invoke the existing generation path/quota. Server authenticated time, last visit and last nudge admit at most one offer after five hours, inclusive boundary. Entries are owner-serialized and request-idempotent, including concurrent devices/tabs; pending generation/assessment suppresses admission. No push permission, notification or cron. Offer wire uses legacy `kind: clarification` plus optional `is_offer: true`, so old clients do not render a phantom exercise. Reads do not generate or consume AI quota.

## Real execution

- `go test -race ./...` and `go vet ./...`: pass after backend changes.
- Node full suite: **84 passed**.
- Swift Core: **30 XCTest executions, one existing skipped Go-podcast-wire test, zero failures**, plus **68 Swift Testing tests passed**.
- Actual AppModel lifecycle/cache harness: **68 tests passed**, including new quick-send coalescing/draft preservation and seen receipt logout fencing.
- Actual Go handler JSON → production Swift DTO decoder: **8 states passed**, including new offer and existing empty, exercise, legacy, pending, failed, completed assessment and reset.
- New Go tests cover exact five-hour boundary, duplicate entry, source assistance/reveal idempotency, seen revision, pending suppression, 12 concurrent authenticated entries, owner mismatch and storage failure. Existing CSRF/revocation suites still pass.
- Real Chromium synthetic-transport test: answer masking/reveal and reload persistence, exactly one rapid-tap practice POST, draft preservation, stable DOM identity, no rehydration entry animation, offscreen unread, scrolled-up preservation, jump/seen receipt, 390px layout, dark mode and reduced motion: pass.
- Signed/ad-hoc **Release iOS simulator** build succeeds, `codesign --verify --deep --strict` passes. No device provisioning claim.
- Release simulator XCTest: five distinct Coach tests passed across runs: contextual pending/correction, populated chat/keyboard, old-answer collapse/reveal, source navigation/return, accessibility/Profile. Latest rebuild also passes dark/accessibility test with actual simulator dark appearance. Earlier `-AppleInterfaceStyle Dark` alone did NOT make it dark; the actual dark capture below was verified with vision.
- `git diff --check`: pass.

## Evidence (actual captures, synthetic content)

Web:
- `/Users/tinyserve/.hermes/cache/scratch/coach-chat-evidence/desktop.png`
- `/Users/tinyserve/.hermes/cache/scratch/coach-chat-evidence/mobile-dark-reduced.png`

Native keyboard/pending/correction:
- `/Users/tinyserve/.hermes/cache/scratch/coach-chat-evidence/native/F7BC3288-EC44-4902-B123-DA8D862795D9.png` (keyboard)
- `/Users/tinyserve/.hermes/cache/scratch/coach-chat-evidence/native/0C57F3BA-4EE1-4878-B6D6-8FA2B1D2E85A.png` (contextual correction)
- `/Users/tinyserve/.hermes/cache/scratch/coach-chat-evidence/native/4E1C19A3-A7E2-4D19-88C4-B4400B28B84A.png` (pending)
- `/Users/tinyserve/.hermes/cache/scratch/coach-chat-evidence/native-final/5F1FF396-4B7E-49A0-AA44-E491BDBBEFC9.png` (old answer explicit reveal)
- `/Users/tinyserve/.hermes/cache/scratch/coach-chat-evidence/native-dark/483F1870-48C2-4818-8B81-8BC56E1DFB57.png` (verified actual dark, accessibility size)

Result bundles:
- `/Users/tinyserve/.hermes/cache/scratch/coach-chat-ui.xcresult`
- `/Users/tinyserve/.hermes/cache/scratch/coach-chat-final-ui.xcresult`
- `/Users/tinyserve/.hermes/cache/scratch/coach-chat-verified-ui.xcresult`
- `/Users/tinyserve/.hermes/cache/scratch/coach-chat-dark-ui.xcresult`

## Independent completion review

Reviewed the actual candidate diff against `1c917c9e1ef2af116fd6b561acb649054846d3e1` in this worktree only. Additional RED→GREEN regressions found and fixed:

- Web and actual native AppModel silently ignored HTTP 401 on quiet seen receipts. Both now revoke through their existing session failure path; native also rejects already-cancelled receipt tasks and stale prior-owner viewport turns before transport.
- Web receipt renders removed the arrival class before a frame could animate. Arrival identity now lasts through `animationend`, and real Chromium requestAnimationFrame samples demonstrate intermediate opacity for incoming content while initial history stays opacity 1 with no animation.
- Web ordinary background return did not consult server entry admission. It now resets the foreground-entry guard on hidden visibility, leaving the five-hour decision and free offer entirely server-owned.
- A web receipt loop could continue sending subsequent rows after backgrounding during a delayed receipt. The loop is serialized and rechecks current visibility/scroll conditions before each next request. A delayed synthetic transport regression caught this failure.
- Source-free offers accepted fake source disclosures and assistance. Invalid source-free reveals now conflict without events/receipts; event-ring and post-answer no-regrading assertions were added.

### Additional real execution

- Full Go race suite and vet: pass after final backend changes; new CSRF coverage explicitly exercises entry/seen/reveal. Tests cover replay admission, 250-turn/10,000-receipt bounds, 512-event ring, cumulative disclosure counts, post-answer unchanged outcome/assistance, future seen rejection and existing concurrent owner/storage scenarios.
- Node: **85 passed**.
- Swift Core: **30 XCTest executions, one existing skipped wire test, zero failures; 68 Swift Testing tests passed**. Go→Swift Coach decoder: **8 states passed**.
- Actual AppModel: **71 Swift Testing tests passed** after the added revocation, replacement-owner and cancellation regressions. Whole native Python CI also passed **51 tests, one skip** before the last cancellation regression; that last regression was separately rerun in the 71-test harness.
- Chromium browser suite passed twice consecutively with initial/arrival frame samples, delayed background receipt handling, foreground entry, masking/reveal, composer draft, offscreen unread, dark/mobile/reduced-motion emulation. Visibility transitions here are deterministic DOM overrides, not a physical OS background claim.
- Final signed Release simulator run: **3 tests passed, zero failed** (background/reactivation entry + draft preservation, offscreen unread across background + jump receipt, old answer collapse/reveal). Final result `/Users/tinyserve/.hermes/cache/scratch/coach-review-final-ui.xcresult`; `codesign --verify --deep --strict` passes.
- Native evidence exported under `/Users/tinyserve/.hermes/cache/scratch/coach-review-final-shots/`; earlier independent background/scroll captures were inspected with vision. Browser frame evidence: `/Users/tinyserve/.hermes/cache/scratch/coach-chat-evidence/browser-initial-frames.json` and `browser-animation-frames.json`.
- An attempted full Coach UITest batch exceeded the tool's actual 420-second ceiling and left an unreadable/incomplete `coach-review-all-ui.xcresult`; **not counted as a successful run**. Bounded final three-test run above succeeded. Pre-existing unrelated UITest actor warnings remain.

### Remaining release gates (do not describe as complete)

- No simultaneous physical-device/cross-device UI session was exercised; server concurrency and native owner/read-only cache tests are not that claim.
- Native reduced-motion/VoiceOver traversal and native frame-by-frame initial-vs-arrival animation remain unverified. `simctl ui` exposes appearance/contrast/content-size only, not a supported reduced-motion or VoiceOver switch. Desktop `computer_use` capture found no on-screen Simulator window, and app discovery likewise exposed none; no global accessibility setting was guessed or altered. XCTest labels/Dynamic Type are not spoken-output verification.
- Native transition code was scrutinized but no claim of once-only frame-level correctness is made. This remains an explicit release acceptance gate requiring a supported UI/recording harness or owner-assisted accessibility pass.
- No production account, paid provider, personal history, original dirty main/Diktat worktree, deployment or remote branch was touched. Parent must integrate Diktat and decide release readiness; **candidate is not yet fully release-verified**.

## Limitations / independent review gates

This is a tested candidate, **not a claim that every acceptance edge is verified**.

- No paid real model calls: real pedagogical accuracy is not re-evaluated; synthetic fixtures are explicitly not live AI.
- Native UI tests cover core chat, keyboard, reveal and dark Dynamic Type, but do not yet automate two physical devices, background/scrolled-up unread receipts, owner replacement during a viewport callback, or reduced-motion/VoiceOver traversal. Native geometry/animation code needs independent scrutiny and targeted UI tests; VoiceOver ordering is source order, not spoken-output verification.
- Browser dark/mobile and reduced motion are real Chromium emulation; a real mobile OS keyboard/Safari viewport was not exercised. Web focus was tested, native software keyboard was exercised.
- Incoming animation is implemented but native once-only/no-rehydration behavior has not been instrumented frame-by-frame. Existing source/profile snapshots can intentionally show answers after explicit navigation; spoiler masking is the chat presentation rule.
- Seen/source reopen receipt failures currently leave unread/error state or retain an already-authorized disclosure; not every offline timing has UI coverage. Existing 250-turn/10,000-action conversation limits are unchanged; entry receipts count toward the action limit.
- Independent parent review required before commit/release. No Astra review inference was run and no production or deployment verification is claimed.
