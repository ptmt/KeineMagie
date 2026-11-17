# Focused Dictation UX — versioned playback implementation

## Current implementation (2026-11-17)

This section supersedes the presentation-only status below. Playback policy **1** is implemented and locally verified in this worktree. Full Go unit/race/vet and actual Chromium media verification passed through the parent tool environment after the coding subprocess sandbox blocked listeners and Chromium. New policy evidence is in `docs/evidence/dictation-focused-ux/policy/`; historical evidence below belongs to the earlier presentation implementation.

- New web text submissions and explicit **New attempt** requests opt into immutable `playback_policy_version: 1`. Previously journaled create and New attempt requests keep their original policy/body on retry, including absent legacy versions. Absent version preserves legacy web/native attempts. Only the exact integer `1` is supported; null, zero, floats, strings and unknown versions are rejected. A mode change or relaunch never resets the policy ledger.
- `POST /v1/learning/dictations/:attempt/playback` admits owner/attempt-scoped reservation IDs. Actions are `start`, `resume`, `progress`, `release`, `ended`, and explicit mode-change `cancel`. The request contains `id`, `client`, `step`, `fence`, and bounded `offset`; arbitrary fields/URLs are rejected. Admission requires an existing cached asset and never invokes synthesis.
- Four **whole starts** are counted by the server, including the optional final whole replay. Duplicate IDs do not increment the count. Cancelled whole starts remain counted. Interrupted starts retain their identity and best-effort saved offset. The final replay can be started once, within the same four-start allowance; exhausting that allowance explains how to begin a new attempt.
- The durable ledger has its own revision, separate from draft revision, draft mutation IDs, daily generation admission and monthly paid accounting. A 15-second lease permits one active reservation per attempt. The player checkpoints every four seconds, stops conservatively before lease expiry if renewal fails, and requires explicit Continue for recovery. Resume changes the fence; checkpoints also advance it so reordered offsets and old callbacks are rejected. A released or expired reservation remains resumable instead of admitting another start. A live lease held by another client prevents takeover.
- The entire reservation history, cursor and active recovery position are committed under the existing identity/store locks with atomic rename and file/directory fsync before success. Storage retains its existing bounded size; reservation history is additionally capped at 256 identities per attempt, including canceled chunks, while retries/resumes remain available at capacity. This resource bound is separate from the four-whole-start policy and does not limit draft edits. Explicit new policy attempts hardlink owner-scoped cached assets, fsync the directory and keep independent drafts and playback ledgers. Removing the source attempt does not remove those hardlinks.
- Whole mode has no Pause or seek control. Browser/OS interruption remains possible; offsets are untrusted recovery hints, and neither callbacks nor counters establish that someone heard the audio. This is playback admission, not DRM.
- Sentence mode starts at the first sentence and continuously follows the existing sentence/chunk/repeated-sentence plan, with a three-second timer between entries. Labels describe passages, never word alignment. The final whole entry is excluded from the automatic chain and offered explicitly. Mode changes cancel the current reservation without refunding a whole start or resetting the sentence cursor.
- Missing assets require explicit **Prepare audio**. In sentence mode, that gesture authorizes preparation of missing remaining plan assets (including the cached final whole asset if missing), sequentially within one cancellable scope. There is no generation on play, mode change, natural end, navigation, locale change or progress. Preparation notices and budget information stay in the closed About audio disclosure. The existing $10 monthly cap is unchanged.
- Typing remains enabled during playback, checkpoint traffic and preparation. Ledger refreshes merge independently of pending typed drafts. Heartbeat-only changes update controls without rebuilding the textarea. Current passage, whole-start count and elapsed/asset timestamps provide status. Existing journal saves, draft conflicts and recovery/export remain in place.
- New policy hints and status strings cover de/en/ru/es/fr. Legacy hints remain unchanged. Russian policy copy matches the task. The existing top-right **Check** remains provisional and explicit: it flushes the draft and invokes deterministic grading only on activation. No audio end checks a draft.
- Browser cookie/session ownership and CSRF mutation checks remain in place, as does native bearer authentication. Media GET/HEAD revalidate sessions and ownership; HEAD is now correctly treated as a safe read without mutation CSRF. Range transport remains through `http.ServeContent`.

### Verification and reproduction

New implementation tests are in `server/dictation_playback*_test.go` and `web/tests/dictation-policy.test.mjs`. They cover strict policy admission, four starts/fifth rejection, same-ID retry, concurrent tabs, lease expiry/handoff, stale/reordered callbacks, draft/quota independence, sentence ordering/final-once, owner/session/media Range/HEAD checks, failed durable writes, cache reuse, and SIGKILL persistence. Node tests also exercise the player with a controlled clock, autoplay rejection/recovery, mode cancellation, owner changes, stale synthetic events and pending draft preservation. These are unit/handler tests; synthetic events are not browser completion evidence.

`web/tests/dictation_policy_browser.py` and `dictation-policy-fixture.html` are provided for browser verification. They use the actual module/CSS, actual HTMLMediaElement, and real Go handlers via a test-only stdio bridge. The only audio bytes are explicitly synthetic silent WAVs. The suite is intended to exercise HTTP Range, natural media ends, four starts, restart, autoplay/network recovery, tab fencing, the three-second chain, final explicit replay and captures in all five locales. **The suite passed against real Go handlers and natural HTMLMediaElement events.** Ten captures cover whole and sentence modes in five locales; Russian whole and French sentence captures were visually inspected without clipping. The browser also verifies typing persists across whole listens without automatic Check. A preparation-baseline race in the test was fixed by waiting for Prepare to finish before recording paid POST count. One early rerun reported an intermittent fetch error; three subsequent runs, including the final expanded suite, passed with zero page errors.

Commands (from the repository root, with a writable Go cache when needed):

```sh
node --test web/tests/*.test.mjs
cd server
go test ./...
go test -race ./...
go vet ./...
# From the repository root, with the supplied Playwright interpreter:
/Users/tinyserve/.hermes/cache/scratch/coach-history-python/bin/python web/tests/dictation_policy_browser.py
```

Executed results are recorded in `docs/evidence/dictation-focused-ux/policy/verification.json`. Initial subprocess sandbox restrictions were resolved by running verification through the parent tools. The SIGKILL test starts and kills a local child test process after a durable reservation. No acoustic, provider, live AI/TTS, Xcode, push or deployment validation was attempted.

Final executed results: **136 Node tests passed**, full `go test ./...`, full `go test -race ./...`, and `go vet ./...` passed. Browser policy verification passed. Review additionally found and fixed a missing production static allowlist/Docker COPY entry for the new player module and unbounded canceled-chunk reservation history; both were reproduced with failing tests before fixes.

Local staging and commit are performed through the parent tools; nothing is pushed or deployed. Check placement remains provisional pending user approval.

The integration commit `277d7c3` was inspected read-only. Its Dictation delta mainly removes the focused presentation and evidence, while its other changes concern Coach/onboarding and other features. No integration files were copied wholesale, and no Coach/native files were edited.

---

## User correction — presentation implemented; playback policy pending

**This section supersedes the historical presentation below. The requested four-playthrough / automatic-pause behavior is NOT implemented. Do not release this as completion of that request.**

Inspected starting HEAD: `eb20d8304ea69495f1213bf095c2b87b6b8cbef2`. Only this worktree was modified; no push, deployment, native build, provider call or change to the separate combined/Profile worktrees.

Implemented locally:
- Removed the prominent “Через OpenAI API · платно” summary. The existing closed **Об аудио** disclosure retains all source-to-OpenAI, paid preparation, cached replay, retry/cancellation and AI-voice information. No additional consent prompt. Backend monthly budget code is untouched.
- Replaced the textarea placeholder with a separate, restrained Hint card, max-width 60ch, accessible through `aria-describedby`. German, English, Russian, Spanish and French have matching three-sentence guidance. **The current copy describes legacy behavior truthfully; it does not falsely promise four listens or automatic pauses.**
- Removed Check from the footer. Kept the same explicit **Проверить / Check** action at the input's top-right provisionally. It still flushes the draft and calls the existing revision-checked endpoint only on a click/keyboard activation. It is NOT renamed “Готово”, and never fires automatically after audio. Parent/user confirmation of the final trigger/placement is pending. The current Go `/check` handler performs deterministic `dictationGrade`, not AI inference.

### Architecture decision required before playback implementation

The current record has `replays`, **not `full_listens`**. Web `practiceTransition` and native `DictationRecord.transition` both increment it on every segment's `ended` and reset it on mode changes. Go accepts it from client PUT progress. There is no server playback admission/start/end endpoint and no durable active-listen identity or offset. Retrofitting a global cap here would change released iOS and existing attempts; a component-only count would reset or race.

The actual plan is whole → sentence → optional clause/word-group chunks → repeated sentence → … → final whole. Each entry references a separate cached asset; these are NOT word-aligned timestamps. Current Next is manual and no timed automatic pauses exist. Keep “По предложениям”; do not advertise “по словам”.

Proposed opt-in protocol (not yet implemented):
1. Persist immutable `playback_policy_version` on new explicitly opted-in attempts; absent version stays legacy. Preserve existing attempts and native unlimited behavior. A new attempt gets its own ledger while reusing authorized cached audio. Do not reset the ledger on mode changes.
2. Add owner/attempt-scoped idempotent playback reservations, separate from mutable draft revision and the paid-generation ledger. Admit at most four whole-listen identities. Keep the active identity and saved position across interruption, reload and retry; duplicate starts or resumed interrupted listens do not consume another slot. A genuine natural completion is acknowledged idempotently. A failed start/network error is not a completed listen; expose recovery rather than claiming it was heard.
3. Serialize reservations under the existing durable transaction lock. Fence late callbacks with owner, attempt, asset and reservation identity; use a session lease/generation for device handoff so two devices cannot independently spend the same slot. Distinguish stale clients, expired handoff and unresolved completion. Preserve typed journal data independently during all playback/checkpoint traffic.
4. Whole mode hides Pause and native media controls, exposes no manual seek UI and does not reset src on resume. Browser/OS interruptions cannot be prohibited and audio events cannot prove a human heard it; truthful interrupted-state recovery is required. Do not automatically submit the draft at the fourth end.
5. Sentence mode schedules the existing plan's cached assets continuously with explicit timed pauses at existing boundaries, retaining typing. Exclude the final whole entry from the automatic chain and offer it once explicitly after the sequence. Pause duration is an unresolved product parameter; do not imply a word-timing model. A generation of any missing asset must remain inside an explicitly authorized Prepare scope, never on play/end/locale/navigation. If not prepared, stop truthfully rather than secretly POSTing synthesis.

Target Russian hints **only after that behavior is implemented and verified**:
- Whole: “Текст можно прослушать 4 раза, без пауз. В первый раз запишите всё, что расслышали, хотя бы отдельные слова или подсказки. При каждом следующем прослушивании добавляйте слова и детали.”
- Sentences: “Слушайте текст с паузами между фрагментами. Записывайте на ходу. В конце можно ещё раз послушать текст целиком.”

Required future tests: server fourth admission/fifth rejection, reload and fresh attempt, owner isolation, duplicate/reordered start/end, two-device handoff, interrupted resume and failed starts, draft saves during all plays, and legacy web/native backward compatibility. Exercise natural real HTMLMediaElement events with clearly labeled controlled WAV fixtures for pause timing, sequence transitions, final explicit replay, seek-control absence and recovery without new paid POSTs. Dispatched fake `ended` events alone are not completion evidence. No acoustic fidelity claim from silent fixtures.

### Verification of this presentation-only correction

- Strict red/green Node tests first caught the prominent paid summary and absent hint/header placement. Full Node suite: **124 passed, 0 failed**.
- `go test ./... -run 'TestDictation' -count=1`: passed; backend unmodified, opt-in live/provider tests not enabled.
- `dictation_correction_browser.py`: passed; actual module/CSS, five locales, no overflow, no placeholder, closed privacy details, no footer Check, visible keyboard focus, zero automatic audio/check requests, exactly one explicit keyboard Check. Captures and JSON: `docs/evidence/dictation-focused-ux/correction/`.
- Existing focused lifecycle and five-locale preparation-geometry suites: passed, no page errors. Cancellation fixture wait enlarged from 1s to 10s after a loaded-host click raced the simulated completion; production cancellation code unchanged.
- Existing real HTMLMediaElement suite: passed using a synthetic **silent** 3-second WAV and HTTP Range; verifies unchanged legacy pause/resume/end/replay behavior, not policy v2 or real voice.
- Inspected actual Russian desktop/mobile screenshots: readable neutral hint, no prominent paid line, no bottom Check, provisional top-right Check and no clipping.

## Historical candidate record (before the user correction)

## Status and source

**Web only. Not pushed, published, or deployed. User visual approval is required before release.**

Isolated worktree: `/Users/tinyserve/Projects/KeineMagie-dictation-focused-ux`, branch `candidate/dictation-focused-ux`.
Freshly fetched source: `origin/main = e8ed89e` (documentation), following `b52c48d`.
The concurrent integration worktree at `b1dcc90` was inspected read-only and had uncommitted native changes, so it was not used as a supposedly clean/validated baseline. Its committed Dictation-only onboarding, durable creation-resume row, loading/empty guards and History Refresh menu were carried forward, with their mount tests. No Coach/native files or other worktrees were changed.

When integrating, merge this focused delta, not a wholesale copy of the worktree: preserve later integration changes, especially onboarding, resumed drafts and menu Refresh. This candidate does not include the parallel native/Coach release.

The supplied `img_e2e8a4372ae0.jpg` was opened and inspected. Baseline runtime captures reproduce its flat action hierarchy using synthetic content. All after captures render the actual production `dictation.mjs` and stylesheet, not a mock layout.

## Behavior

- An open exercise has one title, a quiet History back action and an accessible overflow for New attempt / Delete attempt. Delete retains confirmation. Checked results offer New attempt contextually after feedback. Escape returns focus to the summary; Tab/focus leaving and outside pointer clicks dismiss the overflow.
- Compact pressed-state Whole text / By sentences controls expose only the current practice panel. Existing practice transition semantics and one shared draft remain intact. No new content or audio is generated on mode/locale/navigation changes. While preparation is pending, explicitly cancel before changing modes.
- The player has one state-driven action: **Prepare audio → Play ↔ Pause → Replay**. Pausing and resuming the same asset preserves its position. Replay after end is scoped to the current attempt/asset. Speed stays in the player row.
- Before every uncached preparation, **“Via OpenAI API · paid” / “Через OpenAI API · платно”** is visible beside the action area, not behind the overflow. Its disclosure retains the complete existing notice: source text is sent to OpenAI, API charges apply, saved replay makes no new paid request, cancellation/retries may still cost, voice is AI-generated. No exact price or cost-free cancellation is promised. Server admission/budget enforcement, privacy boundaries and paid endpoint contracts are unchanged.
- No autoplay or automatic paid retry. Preparation uses the existing abort signal and busy gate. Pending text/spinner occupies the same row; Cancel replaces speed within a reserved column. No fabricated percentage, duration or progress. Reduced Motion uses a static indicator.
- A failed preparation offers the same explicit Prepare action with a specific error. A media failure retains a replay retry; only a scoped HEAD 404 returns to explicit preparation with the paid disclosure. HEAD 401 keeps the existing identity-revocation path. Direct media URLs and browser Range transport remain intact.
- The textarea starts at 140px, grows with supported native content sizing, caps at 45vh and remains manually resizable. Check becomes the primary action when there is text; empty Check is disabled. The listening action is primary before writing; after checking, New attempt is primary.
- “Show original” is quiet. Before checking, confirmation explicitly says this counts as help; the existing reveal endpoint records assistance. Checking shows comparison feedback, **not the complete original automatically**. The complete original requires an explicit reveal (or a previous assisted reveal). Opening a checked original does not change assistance retroactively.
- Existing owner-scoped journal, retries, revision conflicts, recoveries, export, pending creation identity and attempt identity remain in place. New attempts preserve prior attempts and cached audio. History navigation waits for saving rather than discarding an unsaved draft.
- All new labels are present in German, English, Russian, Spanish and French. Interface locale does not translate source or learner text.

## Executed verification

- `node --test web/tests/*.test.mjs`: **123 passed**, 0 failed. Existing Node experimental localStorage warnings remain unrelated to Dictation.
- `go test ./... -run 'TestDictation' -count=1` from `server`: passed. Opt-in live/provider fixtures were not enabled. No backend changes.
- `web/tests/dictation_focused_browser.py`: passed with no page errors. Real controller + deterministic in-process API/media; create → explicit preparation → play/pause/resume/end → write → mode switches → check → explicit reveal → new attempt → saved draft return. Also empty onboarding, paid-request count, five locales at 390px, assistance confirmation, error/retry/cancel and keyboard menu.
- `web/tests/dictation_focused_geometry_browser.py`: passed in all five locales at 390×844. Textarea rectangle is identical before/during preparation; no horizontal overflow; Reduce Motion suppresses spinner animation.
- `web/tests/dictation_focused_media_browser.py`: passed using a **synthetic silent WAV through a real Chromium HTMLMediaElement**, not provider audio. Verified click-started playback, paused time stability/resume, natural end/replay, navigation removing media src, and real `Range: bytes=0-` requests. Only one explicit synthetic preparation POST.
- Outside-click overflow dismissal separately exercised; final Russian desktop/mobile captures made. `git diff --check` passed.

The strict red/green tests caught the missing focused player initially and the cached-media 404 recovery gap before their implementations. Browser tests caught stale Replay labeling across a new attempt and a CSS-generated back-arrow changing the accessible History name; both were corrected and rerun.

Existing opt-in backend browser scripts were updated for the new player/menu/reveal selectors but were **not run against a live TTS/backend fixture** in this task. The tests above make no production performance, speech quality, or pedagogical accuracy claim. No private history, OpenAI calls, Xcode, deployment or provider credentials were used.

One combined test command hit its 120-second wall budget during host contention after all 123 Node tests had passed; the browser suites were rerun separately with a sufficient bounded budget and all passed.

## Visual review and evidence

Evidence is in `docs/evidence/dictation-focused-ux/`:

- Matching Russian before/after: `before-desktop.png`, `before-mobile.png`, `after-ru-unprepared-desktop.png`, `after-ru-unprepared-mobile.png`.
- Writing: `after-ru-mobile.png`; preparation: `preparing-ru-mobile.png`.
- `after-empty.png`, `after-menu-mobile.png`, `after-sentence-mobile.png`, `after-checked-mobile.png`, `after-revealed-mobile.png`, `after-error-mobile.png`.
- Machine results: `result.json`, `geometry-result.json`, `media-result.json`, `node-all.log`.

Self-review inspected the actual captures: the original full-width paragraph and simultaneous Prepare/Play/Pause controls are gone; the exercise, audio, draft and next action now fit together on the mobile viewport. Paid disclosure remains visible. There is no replacement teaching card or decorative hero. Checked comparison remains readable without exposing the entire original first.

The official Astra/max independent-review launcher was checked with `--help`, then `--check`. It was **blocked before inference by `ImportError: hermes_cli.oneshot`** in the installed review runtime. No alternate model was used and no independent-review success is claimed. Self-review plus reproducible runtime evidence is available for parent/user review; this blocker is not a deployment authorization.

## Reproduce locally

Serve `web` on loopback port 8876, then run the three focused browser scripts with a Python environment containing Playwright/Chromium. The tested interpreter was `/Users/tinyserve/.hermes/cache/scratch/coach-history-python/bin/python`.

The synthetic fixture is `web/tests/dictation-focused-fixture.html`; it imports the real module/CSS, supplies no credentials and does not call provider APIs. `?empty`, `?locale=ru`, and `?realmedia` select test states. Real-media tests intercept the local media URL with generated silent WAV bytes. The fixture toolbar is explicitly labeled synthetic and is not production UI.
