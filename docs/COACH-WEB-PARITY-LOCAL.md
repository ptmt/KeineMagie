# Coach web parity + meaningful vocabulary clues — local candidate

2026-11-22. Worktree `/Users/tinyserve/Projects/KeineMagie-coach-web-parity`, branch `candidate/coach-web-parity`, exact base `54fee24259c1bd6354e18e1434e45c77ac23a2e3`. This preserves the accepted native soft-red candidate, bold/glass ancestor and real activity/context-translation integration. No push, deployment, Apple upload, paid provider/TTS call or production-data mutation. Unrelated compact-audio candidate `ba61d0ec` was not cherry-picked. The original dirty worktree was not edited.

## Implemented

- Neutral immutable task on the left; literal submitted answer on the right, including whitespace/newlines/emoji; separate assessment on the left. Incorrect gets a restrained red border/light red fill; correct green; learner purple. Answer editor is outside the task bubble, so Check does not change task height.
- Restrained 760px maximum conversation width, scrollable conversation and compact composer/answer controls. Existing contextual plus menu, all five actions, route navigation, draft/caret retention and owner reset remain intact. Current results are visible; old results remain explicit reveal. Active/pending tasks remain reachable outside rolling history.
- Pending dots and receipt-targeted Stop in composer. A failed transport/storage response replaces typing with a neutral error, never an invented verdict; Stop remains for unresolved receipts. Discussion draft stays intact.
- CSS translucent composer uses `@supports` backdrop-filter and an opaque baseline; reduced-transparency removes blur. This is web CSS, **not native Liquid Glass**. Existing native Liquid Glass/soft-red styling is inherited unchanged.
- Fixed 30px weekly strip calls the integrated real `/v1/learning/activity` endpoint with owner fence and timezone/week. Locale-aware calendar, stale-response rejection, immediate scope clearing, refresh on return/visibility and restored detail-button focus. Daily breakdown distinguishes retained counts, unavailable and unsupported sources. Podcasts remain **Not supported**, not fabricated listening data or zero completeness.
- Real `context_translation` target/answer-language semantics preserved; tests highlight only the target word. No scheduler, calibrated difficulty or fabricated skill-level metadata was added.

## Vocabulary ambiguity / two-client contract

New vocabulary cloze generation supplies additive `clue`, `clue_kind` (`gloss`, `synonym`, `context`) and `clue_language`. A gloss uses interface locale; synonym/definition/context uses the source learning language. Model instructions require a meaning-bearing clue rather than a grammatical category. New-generation admission rejects missing/category-only clues and wrong declared language. Existing grounded decoder also rejects leaking expected answers through visible instruction/prompt/clue.

Legacy 9/11-field schemas still decode; new 12/14-field schemas require complete optional field groups. Existing saved tasks are not mutated, regenerated or rejected for missing clues. There is no automatic paid retry for rejected generation. Public payloads include a visible message fallback for old clients that ignore additive fields; new web/native separate that exact suffix into compact clue text without changing stored instructions. Both clients render supplied text, never invent a clue or expose hidden answers.

Assessment receives the visible clue and exact learner answer, with original source retained for grounding. The contract explicitly accepts grammatical, contextually matching alternatives rather than requiring a hidden source word, and permits `ambiguous_exercise` / `insufficient_context` for underspecified tasks. Tests verify the real request contract and synthetic correct/uncertain decoding, **not live model linguistic performance**. Deterministic category/language checks cannot prove arbitrary semantic adequacy; real model quality remains unmeasured.

The screenshot sentence “Ich mache ein ___ bei euch.” has no uniquely established answer. Test occurrences of “Praktikum” and “Traineeship” are explicitly synthetic fixtures, not a claim about the user's task.

## Actual verification

- Baseline archive at exact base: Node **177 pass / 1 skip**, `go test ./...` passed. Original worktrees were not stashed/reset.
- Final Node: **187 pass / 1 skip**, zero failures (188 total).
- Full Go **`go test -race ./...`** and **`go vet ./...`** passed; race run 101.595s. Includes clue admission, legacy decoder, atomic field groups, five gloss locales, hidden-answer rejection, alternative/uncertain assessment contract and no-hidden-retry tests.
- Full native Core: **113 XCTest, 5 skipped, 0 failures**, plus **89 Swift Testing passed**. Added five-locale clue decoding and old-client fallback separation. Unsigned iOS Simulator Debug app build passed. Actual Go→Swift wire script passed all ten fixture payloads, including context translation and legacy.
- `coach_parity_browser.py`: actual app/modules, synthetic local HTTP, Chromium 1280/390 × light/dark; typed exact answer, immutable task height, pending/Stop, neutral error/cancel, draft, historical opt-in reveal, menu keyboard/Escape, 30px strip/details, refresh/focus, reduced transparency/motion, shortened 520px viewport and logout privacy clearing passed.
- `coach_go_browser.py`: **real Go handlers/stores and production static asset handler**, disposable local owner and intercepted synthetic provider; real generation → browser typed answer → assessment → retained activity. Exactly **2 synthetic provider calls**, 1 retained Translator + 1 Coach completion; Podcasts unsupported. This caught and fixed the new module's missing production static allowlist/Docker copy.
- Existing `coach_menu_browser.py`: all five exact action payloads, draft/caret, keyboard/Escape/outside click, five locales × two widths, 44px targets; passed without JS errors.
- `git diff --check` passed. Source/security self-review in this one-shot subagent; no independent reviewer verdict is claimed.

## Runtime previews

`docs/coach-web-parity-evidence/` contains **27 unmodified browser PNGs** and synthetic action receipt. Representative final images were opened and inspected, not reconstructed from markup:

- `1280-light-incorrect.png` — desktop final hierarchy and restrained error styling.
- `390-dark-incorrect.png` — mobile dark incorrect.
- `1280-dark-pending.png` — typing + composer Stop.
- `390-dark-error.png` — final neutral error without stale typing, literal answer/draft retained.
- `390-light-canceled-reduced.png` — reduced-transparency fallback.
- `go-clue-active-mobile.png` / `go-clue-correct-mobile.png` — real Go-generated synthetic clue and green assessment.
- `go-activity-breakdown-mobile.png` — real Go retained-source breakdown.

Live guest Translator/Coach was inspected read-only; no signed-in production data or inference was accessed. Production is older than this local candidate. These PNGs are local synthetic-runtime evidence, **not production screenshots**.

## Reproduce locally (no paid calls)

From this worktree, run `node --test web/tests/*.test.mjs`; from `server`, run `go test -race ./...` and `go vet ./...`. Browser scripts need Python Playwright/Chromium. Verified interpreter: `/Users/tinyserve/.hermes/cache/scratch/coach-history-python/bin/python`. Set `COACH_PARITY_EVIDENCE` to a scratch evidence directory for `web/tests/coach_parity_browser.py`; run `web/tests/coach_go_browser.py` and `web/tests/coach_menu_browser.py` with the same interpreter. The Go browser runner opts in to `TestCoachWebParityFixture` and starts/stops a disposable loopback server; no production credentials are needed.

## Remaining limits

No publication. No real-provider quality measurement, Safari/WebKit or physical mobile keyboard/VoiceOver certification. Reduced viewport/focus is browser evidence, not a physical software-keyboard test. This change compiled native and tested DTOs/wire; inherited native Release UI suite was not rerun. Overnight rollover was not waited out. Unsupported Podcasts remains the known feature gap, not silently counted as complete parity.
