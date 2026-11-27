# Dictation: full ordered timeline — local candidate

**Shipped 2026-11-27:** integrated into `c3334db432e18ee81c50723fe2e0d312494124bb`, web/backend deployed and iOS 1.0 (2860.1.40) uploaded to Apple. See [coherent release receipt](COHERENT-OPTIONS-RELEASE.md). Below is the earlier local verification checkpoint.

Branch `fix/dictation-full-timeline`, isolated worktree `/Users/tinyserve/Projects/KeineMagie-full-timeline`.
Base is fetched `origin/main` **`0db893ecc3078dc45345482361ecf5c3470e6ff7`**, verified to contain recovery `67da4fb3b883a0a61b890fa1e823775abb7ce5ac`, recovery documentation `63e8a1689df43591829960123c007c84e313306a`, and the paid-attempt prevention changes. The original dirty worktree was not edited. No backend, schema, budget, deployment or provider configuration changes.

## Result

The policy-2 sentence timeline now retains the entire actual ordered plan: initial whole reading, every earlier/current/later sentence and fragment, optional final reading. Both web and native had separate sliding windows; both are removed, including the five-child cap and flat-legacy clipping. Group headings require actual sentence/fragment provenance. Mixed and unmapped plans remain in source order without invented sentence associations.

Web keeps the same phase-row DOM objects through playback and draft updates, scoped by owner epoch, attempt, plan and locale. Long plans use ordinary document scrolling with no inner viewport or default collapse. Same-attempt redraws preserve document scroll, draft focus and selection. Existing manual Next, Stop, request/owner fences and explicit Check remain unchanged.

Completion and partial counts come from distinct planned steps with accepted `ended` receipts. Admission, cursor advancement, stopped receipts, extra replays and unknown intent do not complete a policy-2 planned repetition. Partial counts are visible on incomplete earlier rows; each fragment exposes its planned progress accessibly. Current repeat wording is not shown merely because an idle cursor points at a repeat. Native uses the same full-plan order and truthful planned-ended progress.

A discovered existing dark-detail foreground defect was reproduced and corrected locally: title text was RGB 32/33/36 on RGB 24/24/27. The scoped detail foreground now passes the browser contrast check; dark navigation and focus remain readable.

## Executed verification

Evidence: `docs/evidence/dictation-full-timeline/`; `source-hashes.json` identifies the tested source files.

- **RED web:** baseline rendered only 5 of 9 phases initially. A second baseline run reached actual middle playback and showed only Sentence 3 / Fragment 3.1 and Sentence 4 / Fragment 4.1; both earlier 1.1 and later 6.1 were missing (`web-middle-red.log`).
- **GREEN Node:** 201 tests, **200 passed / 1 existing skip / 0 failed** (`node-tests.log`). Includes a new RED→GREEN planned-versus-extra/unknown intent and partial-count test.
- **GREEN real-media web:** actual mounted app modules + real Go handler/ledger + generated silent WAV, Chromium and Playwright WebKit. Nine ordered phases remain before/during/after middle playback, same row identities, durable ended counts and reload, no implicit Next or Check. Full-page PNGs cover 390/1100 widths × light/dark for both engines (`result.json`). This harness uses a synthetic bearer bridge; it is not browser-cookie authentication acceptance.
- **GREEN state matrix:** **60 mounted cases**, both engines × mapped/flat/mixed provenance × ten saved states. Twenty-four fragments, eight per sentence, three repetitions, earlier skipped/partial rows, restored active and repeat-ready states, writing, Stop/pending Stop, checked/final/final-ended. Same-owner explicit New attempt and separate owner reset clear old completion/DOM state. Focus, selection, document scroll, dark contrast and no unintended POSTs checked (`state-matrix.json`). These are explicitly synthetic ledgers, not evidence of natural media completion.
- **GREEN existing natural-media regression:** two/three repetitions, actual gap, manual Next, extra replay, lost Stop acknowledgement and reload recovery, explicit optional final, draft and assistance ledger; five locales at narrow/desktop widths (`manual-regression/browser-result.json`). Only generated silence and synthetic assessment are used.
- **RED→GREEN native Release UI:** reused existing iPhone 17 / iOS 27.2 simulator `93E1113F-6736-4CCB-827D-0E2F1C3876EA`, no clones or parallel simulator tests. Baseline failed at missing Fragment 3.1. Changed app passed **1/1 targeted UI test**, retaining all six fragments through manual middle playback and future-row navigation (`native-red.json`, `native-green.json`). Actual dark runtime PNGs inspected; simulator shut down afterward. The pre-existing main-thread audio-session warning remains. This is targeted normal-size native acceptance, not a full native regression, small-device/Dynamic Type, physical-device or spoken VoiceOver claim.

## Reproduction and harness notes

Use an environment with Playwright **1.60.0** and its installed Chromium/WebKit binaries. An unpinned later Python/Playwright environment requested an absent WebKit binary; the final runs used the existing pinned environment, not a substitute engine. Set `TMPDIR=/Users/tinyserve/.hermes/cache/scratch`.

```sh
node --test web/tests/*.test.mjs
python web/tests/dictation_full_timeline_browser.py
python web/tests/dictation_timeline_states_browser.py
DICTATION_MANUAL_EVIDENCE=docs/evidence/dictation-full-timeline/manual-regression python web/tests/dictation_manual_pacing_browser.py
```

Native fixture: existing `TestDictationNativeIntegrationFixture` on `127.0.0.1:8799`, fresh scratch directory, generated WAV only. Pass its path to XCTest via **`TEST_RUNNER_KM_DICTATION_NATIVE_FIXTURE_PATH`**; the first setup attempt used the unprefixed variable and failed to find the file, not a product regression. Run `DictationManualUITests/testEntirePlanBeforeAndAfterMiddlePlayback` in Release with parallel testing disabled. No native publication is needed to review the web artifact.

## Publication boundary

No push, deployment, production API call, paid speech/inference, ledger recovery or Apple upload was performed. Production `$8 unknown reserve / $2 released / $10 cap` is the supplied preservation requirement, not a fresh live observation by this task. A later release must coordinate with the active prevention/deployment work, re-read current main and preserve the recovery-aware writer and live ledger. Re-review integration with parallel Dictation options/default-repeat UI work, especially shared `web/dictation.mjs` rendering and localization; this candidate does not change repeat defaults or menus.
