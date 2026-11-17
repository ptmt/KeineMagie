# Translator result controls — verified release

## Scope and base

2026-11-17. Fresh worktree `candidate/translator-result-controls` from fetched `origin/main` at `5d532e9118193874175f9d9b339d7e6e3ec1a8c6`; verified ancestor `f787b40e044ddd44b62c5557a1a7a7e78443425c`. The original dirty `/Users/tinyserve/Projects/KeineMagie` was not edited. Local candidate only: no push, deployment, Apple upload, live provider calls, TTS, credentials or private-history access.

The subsequent clarification resolves the templates bullet: Friendly, Formal and user templates belong **inside the source block footer**. Their existing horizontal strip, selection, custom add/manage controls and request instructions remain unchanged.

## Behavior

- Native input clearing already retained `result`; regression tests now protect clear, pending receipt, subsequent typing and completed output. Clearing does not delete history, cancel accepted work or change the accepted receipt.
- Followup context now belongs to the displayed/saved result, not the mutable input. An applied proposal stores its source and translation together. Empty/new input cannot silently become the source for an old output. Existing exact-ID retries, owner/epoch checks, immutable originals and paired explicit Apply are retained.
- Opening either saved history discussion only selects that record. It does not replace the composer, direction or result. Only explicit Apply may replace the working pair; presenting/typing performs no inference.
- Clarify is a quiet text action **inside the output card footer**. Its footprint is reserved even when no action is available; there is no conditional sibling List row.
- History copy and clarify are trailing, separate icon-only 44-point buttons with existing localized accessibility names. Copy writes the exact stored translation. Symbol scaling is bounded to avoid overflowing the reserved touch lanes at accessibility text sizes; content and footer text still use Dynamic Type.
- Web already has the style row inside `input-panel` and clarify inside `output-panel`. Its clear button and input handler did call `resetResult()`: the small companion fix removes that unwanted coupling and anchors followups to the saved/applied source. Existing web history navigation is not redesigned into a new history-discussion UI.

## Entry flicker: reproduced cause, not a delay workaround

`MainTabsView` resumes the outbox on entry/foreground. Previously `drainTranslations` published `translationSending = true` **before** checking for any due queued item. Empty/completed/backoff queues could therefore show the animated result skeleton for a task hop. The output view itself already had stable identity; cache placeholders and mounting were not the cause of this reproduced pulse.

The real-AppModel Observation regression failed before the change (`idleResumeNeverPublishesFalsePending`) and passes afterward for both empty and completed queues. Sending is now published only after finding an eligible due receipt. No sleep/debounce, hidden loading delay or speculative server change was added. Explicit button acceptance remains synchronous before persistence.

Release baseline was built from the unchanged base archive, then the candidate was built, installed and recorded on the **same** isolated simulator. Both used synthetic cached history plus delayed failing refresh, never real user data.

Evidence root (durable, outside the repository):

`/Users/tinyserve/Projects/KeineMagie-translator-result-controls-evidence/`

- `result-controls-entry/before-cached-entry.mp4`: a visible skeleton flash at encoded timestamp **9.021667 s**, after the result card and cached history were already visible. `before-peak.png` shows the actual three skeleton bars.
- `result-controls-entry/after-cached-entry.mp4`: no corresponding pulse. In the inspected 800×250 interior crop, the post-settlement encoded grayscale mean stays 16; baseline spikes to 38. See `frame-analysis.json` and the retained analysis script.
- `result-controls-entry/after-11.png`: later still capture, actual capture completion **12.4967 s** after launch invocation, retains the card and cached history through the delayed failure.
- `captures.json` records actual wall-clock capture offsets. The early captures are the ordinary OS launch frame, not a disappearing cached result.

**Capture limitation:** simctl video is damage-driven, not fixed-rate. The after movie's last encoded frame is at 3.296667 s despite a longer recording interval; later stills and Release UI geometry tests cover the settled period. The crop measurement is not a whole-screen/frame-perfect proof for every device. A successful cold launch restores saved history; this change does not introduce new persistence of the live output/proposal across process termination. Warm navigation and clearing preserve the live result.

## Verification

All execution used synthetic transport/caches. One existing isolated small simulator, `0C5514DC-1F55-4D9C-836E-A0114903477A`, was used serially with `-parallel-testing-enabled NO`; no simulator swarm was launched. Actual light appearance was set using simctl and restored to the original dark appearance afterward. `-AppleInterfaceStyle` launch arguments alone did not override this simulator's appearance; screenshot filename hints are not proof of theme.

- **99 real-AppModel tests passed** (`native/ci/test_connection_lifecycle.py`): paired source after clear/apply, two history IDs, immutable original, stale legacy apply, owner replacement, 401/logout purge, pending receipts, late response fences, outbox persistence, Coach and podcast/Dictation regressions.
- **72 Core tests passed** (`swift test --package-path native/Core`).
- **54 native Python CI tests ran: 53 passed, 1 skipped** (`python3 -m unittest discover -s native/ci`).
- **19 distinct Release UI tests passed across targeted serial runs**: 6 result-control tests, 4 followup tests, 5 shortcut tests and 4 initial-geometry tests. Logs retain earlier RED and intermediate harness failures separately, not disguised as a single clean suite run.
- Release UI covered all five interface locales, largest Russian Dynamic Type, real keyboard, ordinary/dark/light screenshots, exact app-side history clipboard comparison including whitespace/Unicode, two record discussions, explicit Send/Apply, custom template add/edit/persistence, delayed provider success/error, cached-history refresh failure, warm navigation and offline outbox relaunch. Full result-footer bounds are asserted above the keyboard after deliberate list-edge scrolling; partially hittable buttons are insufficient.
- **113 web Node tests passed**, plus **34 actual Chromium checks** in `web/tests/followup_browser.py`: clear retains result, original-source followup after clear, Unicode clipboard, retry, localization without I/O and owner purge. The browser regression failed before removing `resetResult()`.
- `git diff --check` passed. Native Release build/test bundles and logs are retained under the evidence root.

Two old shortcut UI assertions expected unavailable Coach/Dictation placeholders even though those tabs now ship; updated those assertions to current tab selection/profile navigation. The first output-footer assertion also exposed harmless floating-point `43.99999999999994` bounds and now allows 0.1-point measurement tolerance. A large-type UI swipe initially hit the keyboard/editor instead of scrolling the List; the final test deliberately drags the List edge and verifies the complete action is above the keyboard.

## Inspected screenshots

Relative to the evidence root:

- `result-controls-light-shots/result-footer-after-navigation.png`: actual light appearance, cleared input, source templates inside their footer, retained output with internal clarify footer, trailing history icons.
- `result-controls-final-shots/result-footer-after-navigation.png`: corresponding dark ordinary-size screen.
- `result-controls-final-shots/history-controls-ru-dark-large.png`: bounded trailing icon targets with largest text.
- `result-controls-keyboard-shots/result-footer-ru-large-dark.png`: final large-type result/footer above the keyboard after scrolling.
- `result-controls-entry/before-peak.png` and `result-controls-entry/after-11.png`: actual before/after flicker evidence.

No remaining ambiguity about Friendly/Formal placement. The interpretation that clearing input should **keep** the last translation follows the task's explicit instruction; no clear-history behavior was added. Any release authorization remains outside this local candidate.

## Independent review and released-main integration

Reviewed native `9ddd23bfd18ee7bdade1df47a1f369ec93b9ab86` and web `9c1dd5ffcb9185e4f2a8a63d7c5b4d611664459d` against `5d532e9`. Found and fixed one web behavior regression: the new saved-source request anchor was also being used to decide whether Apply changes the composer. After clearing or editing the composer, a nullable-source proposal therefore displayed translation-only Apply while restoring/replacing source text. A separate `composerSource` callback now controls preview/label/render invalidation; followup requests remain anchored to the saved/applied pair. The actual Chromium regression failed on the original candidate, then passed with the fix, including composer edits after the proposal appeared.

Added real-AppModel backoff and due-receipt regressions. Backoff resume publishes no pending change and performs no additional POST. Due resume publishes pending, preserves the exact receipt, and has a durable attempted snapshot before held transport. Reopening that journal correctly normalizes an interrupted send to `needsDecision`; an initial reviewer test incorrectly expected `sending` and was corrected without changing production behavior. Existing immediate acceptance, suspended persistence, revoked lease, owner/401 purge and paired nullable-source tests also passed.

After parent authorization, fetched and locally merged released main `16fdc165e4381099cb994c4057d05c577d8e8602` (web-tabs source `ade5e02ff9217fdc1b38616633c039432d296b67`) in merge `960dfa6a0efc0ed3343ffb381ea37243a887df6c`. All seven web-tabs `app.mjs` additions are retained. No Coach or passage-group branch was merged. No remote push, deployment or Apple upload was performed.

Post-integration independent execution:

- **101 real-AppModel tests passed**, including the two additional resume regressions; **54 native Python tests ran, 53 passed and 1 skipped**. Log: `independent-native-ci-final.log`.
- **72 Core tests passed** (`independent-core.log`).
- **113 Node tests passed** (`independent-web-unit.log`). An earlier wrong test glob ran zero tests and is not counted.
- **37 actual Chromium followup checks passed** (`independent-integrated-browser.log`); RED/GREEN logs retained as `independent-web-preview-red.log` and `independent-web-preview-green.log`.
- Integrated episode-tabs browser suite passed: 10 locale/width cases, keyboard, history/search, legacy links/citations, single-panel accessibility and zero AI POSTs (`independent-integrated-tabs.log`).
- Native production files remain identical to native candidate `9ddd23b`; inspected existing baseline skeleton, later candidate still, light source/result footers and large Russian keyboard captures. No new native UI run, simulator use or new animation proof is claimed; the simulator slot belongs to the parallel passage-group task. Existing video analysis and timing limitations above remain applicable. An attempted independent video-analysis re-execution required tool approval and is not counted as new evidence.

No remaining material issue found in this reviewed scope. All review logs are under the durable evidence root above; no credentials, private history, paid AI or TTS were used. The subsequently authorized release is recorded below.

## Authorized release — November 17, 2026

- Published reviewed source **`b52c48de26f55b5f12947b3fa4240b212d2d2562`** by normal non-force fast-forward from freshly fetched main `16fdc165e4381099cb994c4057d05c577d8e8602`; read remote main back at the exact source. Scoped 13-file diff and whitespace checks passed. Native App production files remain identical to `9ddd23bfd18ee7bdade1df47a1f369ec93b9ab86`. No Coach daily-chat/passage-group candidate was merged.
- Server CI **44070312609**, job **133994554606**, exact source: **success**, published amd64/arm64. Pulled ARM64 image **`sha256:b88118df4fce0fad6495224bf76091cbb86507d3600ed312703f9a8ab6a940c4`**, verified architecture and exact OCI revision, then deployed backend **before** dispatching Apple upload. Previous actual live image was `sha256:9312ef2ad4d7114598a29ea8bdc696a040f09ddc9848c35e27627d0b73543e30`. Extracted backend executable remains byte-identical: SHA256 `fb26fc854b7afd970c52a83136c2c400fd23b3168e8b77aa4886f40a59059757`.
- Existing original Compose base plus durable `compose.translator.yml` lifecycle retained; full merged-config comparison allowed **only backend image** to change. Nonblocking store/account locks and idle checks preceded backend stop; runner lock acquired after stop, private backup under locks, runner released before replacement while store locks remained through final snapshot. Worker **`sha256:a61794a3d7e74b63d9626c453f3b0bac1b9f9f1351b0bb6349ccf564bded9382`**, all worker/unrelated container IDs, environment, resources/security, mounts, routing labels and private backend/worker-only network preserved.
- Fresh locked inventory: **30 actual durable nonruntime files byte-identical**, one completed job, zero active, **2113 segments / 2113 translations**. Existing single November acceptance budget entry retained: USD 1 reserved, 826 micro-USD reported, at most nine further attempts. Dedicated TTS mount remains read-only; UID/GID **65532:65532**, **0400**, access checked after dropping UID/GID without reading the secret. Host secret mode 0600 retained. No provider/TTS call, new hold, history mutation or credential extraction.
- Public certificate-validated HTTPS: **health 200**, session/podcasts/subscriptions/Coach/Dictation **401**, source/env/secret/data probes **404**. All **29 runtime assets** match exact source SHA bytes and include **no-store**. Downloaded hash-verified live assets passed all **37 synthetic Chromium followup checks**, including nullable-source paired Apply versus changing composer and exact Unicode output. Full tabs suite on actual HTTPS assets with all private APIs intercepted passed **10 locale/width cases**, keyboard/AX/history/search/legacy citations and zero AI POSTs. Synthetic fixtures are not real signed-in/provider verification.
- Push validation **44070312479**, job **133994554436**, succeeded. Explicit `publish=UPLOAD` dispatch **44070752302** binds the exact source above and succeeded: validate job **133997567123**, upload job **134000454441**. Hosted logs verify **101 AppModel tests**, **54 Python CI tests (53 passed, one pre-build skip)**, **72 Swift Testing Core tests**, plus **58 XCTest tests (one wire skip)**; Release simulator build and all **3 processed-plist checks** passed. Signed archive/export succeeded with **build `2769.84.18`**; Apple **`UPLOAD SUCCEEDED with no errors` at 2026-11-17 11:16:29Z**, signing cleanup succeeded. Processing/tester availability/device installation are not established by upload.
- Final local **113 Node tests passed** with explicit TAP reporter (`node-final-tap.log`). The first formatter assertion incorrectly expected TAP markers from Node's default spec output; all 113 tests had passed, and the explicit-TAP rerun passed both tests and output verification.
- No local heavy Xcode build or simulator action during release: existing reviewed **19 Release UI** tests/screenshots remain the native UI evidence and their timing limitations above still apply. The serial simulator slot remained with passage groups. Original dirty worktree retained its **59 status entries** and all **54 existing file hashes**, also matching the previous release manifest. Other feature worktrees/AnyProgress were not edited.
- Private backup: `/Users/tinyserve/Library/Application Support/tinyserve/services/keinemagie/deployment/release-result-controls-20261117T110418Z/`; archive SHA256 `8042b9e540a7ec88b060a2198f6b5833de3f21b8df12d9b87e9a85ad09f7dc8c`. Saved previous Compose/image enables backend-only binary rollback; never restore stale account data. Rollback not exercised. Release logs/manifests: scratch `result-controls-release/`; private preservation evidence stays outside Git.
- Limits: normal tinyserve regeneration must preserve the explicit durable override; this is not automatic deployment. Existing host FileVault-off/sleep/update warnings remain unchanged. CI reports action Node-runtime migration/macOS-capacity warnings only. One local watcher timed out and was resumed on the **same** run; no duplicate dispatch. Obsidian read initially returned empty despite nonzero size; exact-note hydration/full reread recovered it. No App Review submission or domain change.
