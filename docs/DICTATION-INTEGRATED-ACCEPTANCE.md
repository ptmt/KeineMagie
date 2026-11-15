# Diktat integrated acceptance — historical candidate

**Superseded by [verified production and Apple upload release](DICTATION-RELEASE.md), source `66136702239e98e61ed828e517cb0f7a54b76aca`.** Statements below describe the pre-release boundary, not current deployment status.

Base fetched from `origin/main`: `1c917c9e1ef2af116fd6b561acb649054846d3e1`.
Integration worktree: `/Users/tinyserve/Projects/KeineMagie-dictation-integrated`.
Original dirty main and old candidate were not changed. All-file private backup:
`/Users/tinyserve/.local/share/keinemagie/dictation-integration-backup/candidate-all-20261115-150906.tar.gz`, with matching manifest and tracked binary patch alongside it.

## Human listening acceptance

The owner listened to the **existing** `short-german.wav` and replied **«отлично»**, accepting its acoustic/voice quality. This refers only to the previously generated exact source `Heute scheint die Sonne.`, model `gpt-realtime-2.1-mini`, voice `marin`, SHA256 `708d33490ac4cc0ee19125cd78a22b7a2b138b12474a741fc1f25478513eff6c`. No additional paid generation was made or authorized. Other texts are not acoustically verified by this approval.

## Real audio transport and UI evidence

The integration's opt-in `TestDictationLocalFixture` has an explicit **test-only cached WAV injection**, restricted to the exact accepted text. It creates synthetic local identities and serves the real production HTTP handlers/stores; there are no provider credentials, speech adapter invocations or spending ledgers in this UI fixture. Cached prepare remains the production endpoint. Fixture identities are not real Apple consent.

- Real WAV independently parsed: mono PCM16, 24 kHz, 42,000 frames, 84,044 bytes, mode 0600.
- Authenticated HTTP Range returned 206, `audio/wav`, `Content-Range: bytes 0-43/84044`, 44 bytes. Unauthenticated audio returned 401.
- Actual Chromium **user-gesture click → HTMLAudioElement ended** advanced completed readings. Repeat, pause/restart, guided mode, draft reload, source hidden until Check, exact reveal passed. `web/tests/dictation_cached_audio_browser.py`; evidence `/Users/tinyserve/.hermes/cache/scratch/diktat-cached-browser/`.
- Actual **Release iOS Simulator Diktat screen → AVAudioPlayer delegate completion** advanced the completed-reading count, with the accepted cached real WAV. Whole/guided/pause/Check and draft/add-form relaunch tests passed individually in the v2 run; v2 suite still failed its outdated logout navigation selector. This is not macOS afplay or macOS AVAudioPlayer proof. See final verification below for corrected-suite outcome.
- Exported iOS screenshots were inspected: no clipping; source hidden, `1 completed readings` visible. Evidence `/Users/tinyserve/.hermes/cache/scratch/diktat-integrated-attachments/`, source bundle `diktat-integrated-ui-v2.xcresult`.

## Deployment boundary — NOT executed

Do not enable speech or deploy until the parent's combined Coach review and release authorization. No production account/store/container was changed. The local verification image was built from `server/Dockerfile` and exercised read-only, no capabilities, no-new-privileges as `nonroot:nonroot` (65532), with synthetic data in its own Docker volume. Health 200, authenticated create/readback 200, cached Prepare 200 and Range 206 succeeded. No Piper/Python process or separate speech worker is used by the production adapter/image. Historical worker sources remain nonproduction and excluded from Docker context.

### Single authoritative spending ledger (mandatory before enabling)

Existing immutable acceptance hold:
`/Users/tinyserve/.local/share/keinemagie/dictation-openai-acceptance/dictations/paid-months/2026-11.json`.
It currently has **one USD 1 permanent reservation**, with reported 93 input text, 29 output text and 35 output audio tokens and an estimated 826 micro-USD, not an invoice. Preserve sibling `paid-budget.json` and `one-authorized-attempt`. Do not reset or use another USD 10 allowance.

The server stores its authoritative budget under `dirname(HISTORY_PATH)/dictations/paid-months/`. Therefore deployment must, **while speech is disabled and all relevant budget/generation locks are exclusively held**, reconcile the acceptance reservation into that exact persistent production ledger, retaining entry ID/usage/hold and any preexisting production entries. Fail closed if either ledger cannot be validated. Never overwrite a nonempty production ledger or copy synthetic auth/history; do not use two independently writable budget directories. Verify one hold is counted exactly once and the remaining November allowance is at most nine USD 1 attempts before enabling. Parent release operator must review/perform this reconciliation; no production ledger mutation was authorized here.

Unknown, canceled, crashed, refused, truncated, transcript-mismatched and usage-error outcomes retain their hold; no automatic provider retries or refunds. The cap is an application admission guard, not a provider/invoice guarantee or allowance for other apps.

### Server-only credential permissions

The owner's source credential stays `/Users/tinyserve/.config/keinemagie/secrets/dictation-openai.key` (never client/Git/log output). A host-user-owned 0600 bind mount may be unreadable by Linux UID 65532. **Do not chmod the owner's source to world-readable.** At deployment, use a dedicated secret volume or orchestrator secret with an owner-only copy owned by `65532:65532`, mode `0400` (parent `0700`), mounted read-only at `/run/secrets/dictation-openai.key`. A root-only one-shot provisioner may read the source through a read-only mount, copy its bytes without stdout, then chown/chmod the destination. This is a narrowly scoped proposed operator action, not an executed secret copy. Verify readability as UID 65532 without printing bytes, ensure no unrelated container receives the volume, and remove the provisioner. Keep key path in `DICTATION_OPENAI_API_KEY_FILE`, not a key-valued environment variable or command argument. Review `server/dictation-openai.env.example`; use explicit approved ceilings and fixed model/voice. The UI fixture requires no key at all.

## Review and final verification

Independent read-only review found four issues (failed-cache hydration, stale history, conflict GET401, media GET401); targeted RED/GREEN regressions now cover all four. A second review caught a callback-contract omission (`unauthorized()` versus `unauthorized(err)`); stricter callback tests failed RED, all five call sites were fixed, then Node 101 and actual Chromium playback passed GREEN. Final independent narrow reviewer follow-up **PASS**, independently rerunning 101 Node tests; parent final review remains required.

Executed by the integrator in the actual Xcode environment (the sandboxed fix worker's narrower exclusions are not our final result):

- `go test -race ./...`: PASS; `go vet ./...`: PASS. Ordinary tests skip the explicitly gated paid/live fixtures.
- `node --test web/tests/*.test.mjs`: **101/101 passed**.
- `swift test` in `native/Core`: **50 XCTest tests executed, one intentional skip, zero failures; 68 Swift Testing tests passed**. See `diktat-integrated-swift-final.log` for framework-specific totals.
- Executable actual-AppModel lifecycle harness: **69 passed**, no exclusions (`diktat-integrated-lifecycle-final.log`).
- Native CI unittest discovery: **53 tests, one skipped, no failures**, including lifecycle and localization (`diktat-integrated-ci-final.log`).
- Actual Chromium full-shell Coach, bootstrap, initial geometry, status geometry, episode review: passed. Header regression passed after updating its stale test navigation to open the existing account dialog before clicking the now-dialog-contained recovery button (no product change). This follows the released UI rather than weakening its assertions.
- Chromium cached accepted WAV: actual user-gesture playback ended, repeat, pause/restart, guided mode, journal reload, source hiding/Check, new attempt and deletion passed; no JS page errors. Delayed preparation/rapid mode/logout-during-download fixture passed separately (synthetic silent transport explicitly labeled, not speech evidence).
- Release simulator regression bundle v3: **16/17 passed**, sole failure was the obsolete logout test navigation. All requested existing regression gates passed: Coach AI, podcast production wire/title, three outbox, two catalog, quiet history, all four translator geometry tests.
- Corrected final Release **Diktat 5/5 passed, zero skipped/failures**, bundle `/Users/tinyserve/.hermes/cache/scratch/diktat-integrated-ui-final.xcresult`. Real `AVAudioPlayer` completion including repeated whole reading, guided playback/pause/Check, interrupted late download, logout during late download, pending draft relaunch and add-form relaunch. Exported final screenshot attachments inspected under `diktat-final-attachments/`; source hidden and no clipping. The v3 existing regression results plus final Diktat run cover the same integrated native source fixes.
- All **302 released catalog entries remain semantically byte-value identical**; 66 additive entries. Released Translator/Coach view, bootstrap/CSS, AI assessment and flame artwork paths unchanged. Full 3,538-file original candidate backup manifest reverified with zero changes. No commits/pushes/deploys.

- Final distroless image `sha256:a0f18afa209b1495a3491970ae081a90d9f9a9d11fd95b9c2608e85f04db2813`: health/create/readback and cached Prepare/206 Range rechecked under read-only/nonroot/no-capabilities constraints. A first probe selected an unsaved second-attempt asset and correctly received keyless 503; selecting an actual ready cached asset passed. No fallback or real provider call occurred.
- Actual Go→Swift podcast wire bridge: six tests passed with no skip (`diktat-podcast-wire-final.log`).
- Durable nonsecret evidence copy, review logs, tracked patch and untracked archive: `/Users/tinyserve/.local/share/keinemagie/dictation-integrated-evidence/`. The old worker/provenance and unrelated domain-migration draft were inherited into the new tree for preservation, not staged as a release payload; parent should exclude them when selecting files.

Known nonblocking diagnostics: Node localStorage experimental warning, existing native no-async-await warning, simulator duplicate accessibility class/debugger-version messages, and AVAudioSession synchronous activation runtime warning. No physical-device or cloud signing/TestFlight upload was requested or claimed; simulator Release playback is the verified native boundary.

Before enabling production: reviewed single-ledger reconciliation and UID-readable secret provision described above are mandatory operator gates. They were deliberately not executed against production.