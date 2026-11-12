# Translation clarification verification

## Implemented contract

`POST /v1/translation-followups` accepts exactly:

```json
{"history_id":"saved-owner-record-id","request_id":"client-retry-id","question":"Я имел в виду оружие","locale":"ru","expected_turns":0}
```

- The server resolves the original source, output, direction, style and previous turns **only from the authenticated owner's history file**. No client conversation/response IDs or arbitrary source/output/instructions are accepted.
- Returns the existing parent record with `followups[]`: `request_id`, `question`, `answer`, nullable `revised_text`, `created_at`. The original `text`, `translation`, instructions, ID and timestamp remain unchanged; there is no duplicate history record/job.
- Followups persist atomically using existing history flock/fsync/rename storage and survive reopening/restart. Older history records omit the optional field and remain valid. Owner-private GET history/translation list returns the thread; delete removes its parent and thread together.
- The trusted task answers clarification questions rather than translating the question. Original source/style are data; preceding questions are user messages and answers assistant messages. Question language controls explanation language, falling back to the five-language UI locale. Direction remains the saved RU→DE, DE→RU or DE→DE proofreading direction.
- Personal ChatGPT credential, offered selected model and existing shared daily translation budget (default 100/day) are reused. One account-wide active request is admitted across processes. Followups reserve without charging missing provider/catalog, validation, stale thread, or duplicate completed requests. An inference attempt is charged immediately before send, including failed/incomplete sent attempts. No automatic retry/replay on locale, navigation or reopening.
- Maximum 6 questions per parent, 2,000 Unicode code points per question, bounded JSON body and output, 90-second inference context. Strict schema requires `answer` and nullable `revised_text`, rejects missing/unknown/duplicate/wrong-case fields. Shared bounded SSE reader requires `response.completed`, rejects incomplete/refusal/failure and inconsistent snapshots, preserving literal Unicode/JSON/whitespace.
- Existing browser Origin/cookie/CSRF boundary explicitly covers this endpoint. Revocation is checked before inference and after completion; revoked responses are neither exposed nor appended.

## UI behavior

Small localized **Уточнить перевод / Clarify translation** action lives on the left directly under styles, shown only for a durable current translation. It opens an inline thread and “Добавьте контекст или задайте вопрос” composer. Both user and assistant turns are shown. Suggested replacement is separate, with explicit **Use translation**; it changes the current output/copy/swap only, never the saved original. Saved thread retains the proposal so it can be selected again after reopening. The original remains the history preview. Applying clears the misleading original “Saved” caption.

Same-owner draft/open/selection state survives UI language changes without requests. One pending send is coalesced, failures retain question and retry ID, responses for another selected source cannot replace its output. Editing source/direction clears the visible old association; changing authenticated owner clears all in-memory threads/drafts and aborts pending work.

## Actual execution evidence

No paid/live inference, production mutation, real provider login, key changes, deploy, push or commit was performed. All provider and browser API fixtures below are explicitly synthetic. Real Chromium renders the shipped HTML/modules/styles and exercises real clipboard operations.

- RED: initial server conversation test returned 405 for missing endpoint (expected 403 CSRF), before implementation.
- RED: initial Node followup test could not import the not-yet-created feature module.
- GREEN: `go test -race ./...` → `ok diktat/server` (35.230s); `go vet ./...` → exit 0.
- Full `go test -json ./...` capture: 377 test/subtest runs, 372 pass, 5 environment-gated skip, 0 fail. Capture: `/Users/tinyserve/.hermes/cache/scratch/followup-go-results.jsonl`.
- `node --test web/tests/*.test.mjs` → 64 pass, 0 fail. Includes three new discussion state/dictionary tests and updated shell harness using the real new module. Existing Node localStorage experimental warnings are not failures.
- `web/tests/followup_browser.py` → 18 checks passed: actual two-turn discussion, unchanged original, explicit apply, exact long Unicode/multiline/JSON clipboard, all five locales without extra API work, retained editor selection, failure/retry ID, duplicate click coalescing, saved thread reload, mobile/desktop bounds, edited-source detachment, owner clearing, zero page errors.
- `web/tests/copy_browser.py` → 22 checks passed, including actual system clipboard for a 64,838-character payload and fallback focus restoration.
- `web/tests/run_legacy_browser.py` → all 7 suites passed: browser_smoke 26, directions 19 (all three directions), guest 23, i18n 13, podcasts 41, session 12, styles 13 checks. Older eval fixtures were updated to load the actual new module rather than bypassing it.
- New Go tests explicitly exercise RU→DE, DE→RU and DE→DE conversation payloads, plus cross-owner not-found/no leak, CSRF, exact server source/output/style association, two turns, stable parent storage, repeat request dedupe, stale thread version, empty/overlong/unsupported/unknown-input validation, turn cap, missing provider/catalog/budget no-charge, strict schema and completion cases, sent failure accounting, concurrent request exclusion and actual revocation while inference is pending.
- Real UI screenshots captured and visually reviewed at 390px and 1440px: `/Users/tinyserve/.hermes/cache/scratch/followup-390.png`, `followup-1440.png`. The review confirmed readable discussion below style labels, visible explicit apply control, intact original output, and no horizontal overflow. Long synthetic stress output was tested separately; representative screenshots use the short fixture proposal “Bogen”. Review prompted limiting proposal height and adding a quiet border to the apply action.

## Combined release verification (2026-11-12)

Independent follow-up and episode/profile reviews completed before release. Integrated rerun: Go race **36.557s**, vet clean; **67 Node tests**; follow-up Chromium **19 checks**; independent episode review **83 fixture requests**, navigation **31**, episode **70**, analysis **7 checks**, HTTP i18n **24**, copy **22**, history preview, redesign, podcast design, bootstrap and light/dark visual suites; all seven legacy suites passed. One review assertion raced asynchronous deep-link restoration after a fixed 100ms delay: rerun passed, then the test was hardened to await the exact focused segment and passed again. No production code workaround was needed.

Lock ordering audited: final append holds auth → owner-history only across local read/atomic write; history callbacks do not acquire auth and no provider HTTP runs under the global auth lock. Docker/static allowlists contain exactly **18 public assets**, including both new follow-up files. Production rollout evidence is recorded separately in `COMBINED-WEB-RELEASE.md`.

## Implementation scope

Feature code is isolated in `server/translation_followup.go`, `web/translator-followup.mjs` and `.css`; existing translation SSE decoding was extracted without changing ordinary translation schema. Minimal app/index seams and exact static/Docker asset lists are integrated. Parallel episode/profile work is preserved, not staged or committed by this task. Parent must perform independent combined diff review and coordinate commit/release/deployment. Live personal-provider semantic quality has intentionally not been exercised; synthetic tests prove the contract, not a real model's answer quality.
