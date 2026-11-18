# Native Dictation: explicit Stop and actual-playback status

Local candidate, based on verified-clean `f99168903320dcc213fbf36de7070c6e55e06f26`. No push, deployment, TestFlight, production account mutation or paid synthesis.

## Contract

- Keep the approved one-row native accessory: source symbol, leading title, quiet localized state, independent 44pt transport. No visible timeline, clocks, info button, permanent speed, new search feature or Pause.
- The headphones become a small variable-color waveform only while the real audio adapter reports playback. Admission/download/preparation and automatic gaps do not animate it. Reduce Motion disables the effect; the static waveform and Playing text remain distinct from Ready, Loading, Waiting and Stopped. Labels are translated in German, English, Russian, Spanish and French.
- Active playback, cached-media loading and automatic gaps expose a square **Stop**. Explicit asset preparation retains its existing Cancel preparation action. Navigation/body taps still open the exact attempt without autoplay or draft replacement.
- Stop silences the player synchronously, invalidates callbacks, cancels heartbeat/expiry/gap timers and resets the selected sequence clock. Whole mode returns to offset zero; sentence mode returns to the first chunk, not the current chunk. No `ended` event is sent for Stop.
- **An admitted whole-text start remains spent.** The next explicit whole-mode Play is a new admission at zero and consumes another start. Four starts remain the cap; stopping four times cannot create a fifth. Stop never changes paid generation counters or creates assets.
- A final reading remains allowed only once and still shares the four-start allowance. Stopping it consumes that final permission permanently. In sentence mode, Stop rewinds to the first chunk; replaying the chunks does **not** restore the final reading. This is intentionally not a final-reading resume loophole.
- OS/background interruption remains a separate release/Continue path, preserving the offset and existing admission/count. Tab navigation still has no playback lifecycle meaning.

## Durability and protocol

`POST /v1/learning/dictations/:id/playback` adds `action: "stop"`. Its unique operation ID/client and full-ledger revision (`fence`) form a durable compare-and-swap receipt, separate from listen completion. Optional `admission` names the in-flight/owned reservation. The receipt also denies a delayed start with that ID. Strict JSON/stamp validation, authenticated owner, browser CSRF, live-client lease protection and bounded histories remain enforced. Native requests now send the optional backwards-compatible `X-Dictation-Owner` fence; a mismatch fails before mutation.

Stop clears the active reservation and resets cursor to 1 without changing `whole_starts` or `final_used`. A terminated listen has `stopped: true`, **not** `done: true`. Matching operation retries return the authoritative ledger without a second reset/revision increment. Stale revisions and another client's live lease are rejected, not silently taken over.

The journal stores the exact owner/attempt-scoped reset intent before transport. Immediate silence does not wait for the server. A held admission is generation-fenced and settled before the reset; its late result cannot play. Stop waits for already-issued clock commands before applying the reset, so an older clock cannot overwrite it. Offline failure retains the intent across a cold journal restore, including recreation of AppModel/ContentCache on the same real disk root. Mode-change/Check cancellation waits behind a pending explicit reset before refreshing or resuming a reservation. Before another Play, the exact reset is retried and acknowledged; failure blocks playback rather than resuming a stale offset. Persistence is retried before transport as well. Identity loss purges the existing owner journal and late responses cannot write into its replacement.

The Stop request captures the observed ledger revision synchronously before network I/O. Only acknowledgments of admission/clock requests already captured at Stop may advance that fence; a later refresh cannot adopt a newer foreign revision. Journal writes and acknowledgment clearing compare the persisted Stop operation ID, so a retained controller cannot overwrite or clear a replacement controller's newer Stop. Deterministic cold-restart and held-response regressions were observed RED before these corrections and GREEN afterward.

A competing ledger change fails closed; there is no automatic rebase that could stop a newer foreign operation. This native build and the additive server protocol must ship together. An older server rejects Stop, leaving the durable reset pending rather than silently turning it into Resume.

Only the canceled-before-admission request-context guard was ported from `dfb3dc729d5f29a6afcb711ae0e6dd2aba9b8578`; no web-card branch merge/cherry-pick occurred. The web branch and files remain untouched.

## Preparation-readiness diagnosis

The compact-suite failure was not an unready Go fixture or playback admission lock. In `small-defer-trace.log`, the new attempt's preparation control stayed disabled for 25 seconds with `saving=true`, while `busy=false`, write authorization true, and every playback busy/waiting/playing flag false. The matching application process (88498) logged save ticket 2 finished at `20:58:40.499` with `saving=0`. An earlier failing readiness run also left the newly created server attempt at revision zero. The destination had retained a stale readiness projection. Temporary tracing sources were compared against the preserved pre-diagnostic copies and removed by targeted patches.

Capturing `saving` into the destination closure was tested and rejected: eight isolated launches passed but the combined compact suite still failed (4/5, retained under `acceptance/`). The correction removes the duplicated `@State saving` flag. Readiness now derives directly from `DictationSaveFence.isSaving`, whose active ticket is observable. Finish/reset invalidates the UI; an older ticket cannot clear a newer save. The new observation regression failed before this change, then passed; the final compact batch also includes eight fresh launches in one readiness regression. No timeout increase, sleep, test removal, fixture-response fabrication or permissive readiness bypass was used.

## Evidence boundary

Actual Release SwiftUI/AVAudioPlayer runs use the existing eight-second generated PCM WAV and isolated loopback Go handlers, not provider speech or production credentials. The Go bridge exercises the production HTTP handler/ledger with the actual Swift controller; its output adapter is deterministic and is not presented as simulator audio proof. UI tests separately verify cross-tab Stop, a frozen zero clock, a new zero-based Play and the incremented admitted-start count; gap status and first-sentence restart; unchanged background Continue, draft/navigation and camera behavior.

Raw logs, receipts, native recording and exported unaltered screenshot attachments are under `/Users/tinyserve/.hermes/cache/scratch/dictation-stop/`. Final source hashes and exported-preview mappings accompany the local evidence. Earlier runs remain historical rather than being relabeled as final-source acceptance.

## Final local verification — November 18, 2026

`dictation-stop-evidence/verification.json` records exact commands, result-bundle locations, 403 source-file hashes, screenshot mappings and independent-review verdicts. Source-manifest SHA-256: `d14f792271c467d51977bff5cdf70e2e20060a82ce6747264eb54d198de63ba0`. Source hashes were unchanged across both final Release runs, and no temporary diagnostics remained.

| Gate | Actual result | Receipt under the scratch root |
| --- | --- | --- |
| Normal simulator, coherent combined suite | **9 passed, 0 failed, 0 skipped** | `acceptance2/normal.xcresult`, `acceptance2/normal-summary.json` |
| Small simulator, coherent combined suite | **6 passed, 0 failed, 0 skipped** | `acceptance2/small.xcresult`, `acceptance2/small-summary.json` |
| Core XCTest | 99 reported, 3 skipped, 0 failures | `core-observation-green.log` |
| Core Swift Testing | 82 passed | same Core log |
| Actual Swift → Go handler bridge | 2 passed | `go-bridge-observation.log` |
| Native CI | 64 reported, 1 skipped, 0 failures; contains 119 passing lifecycle tests | `native-ci-observation.log` |
| Go suite, retained unchanged server source | 294 top-level passed, 15 skipped | `go-all.jsonl` |
| Targeted Go race suite, retained unchanged server source | 11 passed, 1 skipped | `go-race.jsonl` |
| Go vet | passed | `go-vet.log` |

These are separate receipts, not a summed unique-test count. The compact six-test run includes the original five-test Stop suite plus the eight-launch readiness regression. Earlier partial/split runs, diagnostic passes and the rejected capture-list attempt remain historical, not acceptance. Independent reviews found and then verified fixes for the offline revision-rebase and late Stop-ack journal races; the final whole-candidate and observable-save-fence reviews both passed.

All **21 PNGs** were freshly exported from these final two result bundles and copied byte-for-byte, then visually inspected (13 normal 1206×2622; 8 compact 750×1334; all RGB). The two Reduce Motion playback images have identical decoded pixels; the actual Settings screenshots show enabled and restored-off states. The retained 14.982-second MP4 is an earlier native presentation clip, not a final-source behavioral receipt: its 597 encoded packets were copied from the original recording without rendering or re-encoding. It has **no audio track**. Neither that clip nor a screenshot proves acoustic silence; the Stop/late-admission assertions and deterministic lifecycle tests supply the behavioral evidence.

The simulator SDK emitted a `_UIGravityWellEffectAnchorView` hierarchy warning; it is retained in xcresult and did not fail or skip either acceptance suite. All 304 protected original-worktree hashes remained unchanged; the web-card worktree remained clean at `dfb3dc729d5f29a6afcb711ae0e6dd2aba9b8578`. AnyProgress was not touched. The loopback fixture was stopped and both supplied simulators were shut down; none were created, cloned or deleted.

Physical-device audio capture, physical camera/permission/handwriting checks, spoken VoiceOver and older-iOS runtime acceptance are not claimed.
