# Focused Dictation UX — local visual-approval candidate

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
