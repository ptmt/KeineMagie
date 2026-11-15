# OpenAI Diktat: one authorized live acceptance (2026-11-15)

## Result

**One real generation succeeded; not a deployment or complete listening/UI acceptance.** Current official OpenAI model documentation independently confirms `gpt-realtime-2.1-mini`, `/v1/realtime`, text input/audio output, 128k context/32k output model bounds, and current text/audio rates. The server used its existing GA WebSocket adapter, no beta header, no `/audio/speech`, no fallback and no paid retry. Dedicated credential was read from its private file only inside the server test process. No secret was printed, copied to source, client, CI or artifacts.

- Exact synthetic source: `Heute scheint die Sonne.`
- Model `gpt-realtime-2.1-mini`, built-in voice `marin`.
- Limits: 100 source characters, 256 output tokens, 12 seconds audio, 45-second deadline; one daily attempt and a persistent exclusive one-test marker.
- Prepare HTTP **200** in **2604 ms**, one provider-adapter invocation. Completed response, audio completion and generated transcript passed the existing same-response/item NFC lexical comparison against the exact fixture. This is not independent recognition of the sound, and does not assert punctuation or strict word timestamps. The exact generated transcript string was not separately retained.
- Actual returned PCM was converted by the production adapter into a valid **84,044-byte WAV**, mono PCM16, 24,000 Hz, **42,000 frames / 1.75 seconds**.
- WAV SHA256 `708d33490ac4cc0ee19125cd78a22b7a2b138b12474a741fc1f25478513eff6c`.
- Three subsequent authenticated cached Prepare + GET pairs succeeded with **zero additional provider invocations**.
- Native macOS **AVAudioPlayer**: prepare/start/completion/success all true, duration 1.75 seconds. This is real AVAudioPlayer playback, **not** verification of the iOS Diktat screen or human acoustic listening acceptance.
- Browser attempts did **not** establish playback: this Chromium harness stayed `readyState=0`, duration unknown; an initial autoplay attempt returned `NotAllowedError`, and explicit clicks/local HTTP did not complete decoding/playback. Do not call web playback accepted. The temporary localhost server was stopped.

## Actual provider usage and durable guard

Returned usage: input **93 text / 0 audio / 0 image tokens**; output **64 total = 29 text + 35 audio tokens**. Current rates yield a rounded-up conservative estimate **826 micro-USD ($0.000826)**, ignoring cache discounts. This is **not a precise invoice amount** or project-wide invoice reconciliation.

The real application monthly ledger was read back and contains **one USD 1 reservation**, retained without refund, plus the reported usage and estimate. The application ceiling remains USD 10 / UTC month (10 conservative USD 1 attempts), not a provider-enforced invoice cap. No automatic retries occurred, and no extra paid cancellation/refusal test was made.

Private persistent evidence store (outside Git and regenerable scratch):

`/Users/tinyserve/.local/share/keinemagie/dictation-openai-acceptance/`

- `short-german.wav` — user-listenable audio artifact (0600).
- `result.json` — nonsecret fixture/results/usage.
- `dictations/paid-months/2026-11.json` — durable USD 1 hold.
- `dictations/paid-budget.json` — daily admission.
- `one-authorized-attempt` — exclusive, retained anti-rerun marker.
- Private fixture-only owner/auth/assets store; no user dictation data.

**Do not delete/reset the ledger or marker to rerun this test.** A future production integration must carry this month's acceptance hold into the single authoritative budget ledger (or reserve its equivalent under reviewed reconciliation), not start a second independent USD 10 allowance. Other independent stores/project spending cannot be bounded by this local ledger.

## Nonpaid verification

- `go test -race ./...` and `go vet ./...`: passed after the live harness was added (ordinary runs skip paid acceptance).
- Focused race tests passed again after extending synthetic Realtime fixtures with German refusal narration and canceled status; cancellation/no retry, refusal/mismatch rejection, usage, cross-process monthly/crash holds, busy admission and cached replay passed. No production behavior was changed.
- `node --test web/tests/*.test.mjs`: **94/94 passed**; Node emitted its existing experimental localStorage warning.
- Full iOS UI tests/current-main merged tests were not run in this acceptance task.

## Compatibility plan — latest release base, never old-base overwrite

Candidate still rests on `d99427b8dd9cf19fae2041066410c686e9d7ab0a`. Latest designated main/release is **`1c917c9e1ef2af116fd6b561acb649054846d3e1`**, combining AI assessment, quiet translator, podcast load and initial geometry. The original dirty `/Users/tinyserve/Projects/KeineMagie` remains on its own branch/HEAD; do not infer that its local `main` branch is the release truth. No other worktree was edited or reset here.

After independent review, prepare a **new** integration worktree at the designated latest release, preserving private candidate archives and applying the Diktat delta three-way; do not reset or push this old candidate as main.

1. Carry Diktat-specific server files plus additive `server/main.go`, `learning.go`, `static.go`, Docker allowlist and Go dependency changes. The inspected latest-base differences in these shared server files are additive Diktat hooks; retain all latest `coach_assessment*` code and tests.
2. Manually reconcile `native/App/AppModel.swift`, `MainTabsView.swift`, `SimulatorSessionFixture.swift`, `ContentCache.swift`, `Podcasts.swift`, matching lifecycle tests and README. Latest changes are material (AppModel 114 additions/24 deletions; simulator fixtures 53/2): retain assessment ownership/state and compact UI, quiet translation/outbox behavior, podcast reload/surface enrichment, and translator initial geometry. Never replace shared files wholesale from this candidate.
3. Merge `Localizable.xcstrings` semantically: retain every latest key/value/locale and add Diktat entries only.
4. Merge additive Diktat routes into latest `web/app.mjs` and `web/index.html`; preserve latest bootstrap, coach modules, quiet/geometry state, HTML/version references and shell tests. Do not overwrite web bootstrap/CSS from the older candidate.
5. Verify race/vet, full web suite including latest coach/bootstrap/geometry browser tests, Swift Core, executable AppModel lifecycle, localization, fresh simulator build and UI tests for both Diktat and latest assessment/quiet/podcast/geometry. Verify actual authenticated web audio playback and iOS screen playback without another generation by using the cached fixture where appropriate. Human should listen to the artifact.
6. Preserve USD 1 hold and private persistence/secret permissions; production key mount must remain server-only, read-only, backend UID-readable. No Piper production path or license-risk weights may re-enter.
7. Independent parent review and separate release authorization remain required before commit/push/publish/deploy. **Nothing was committed, pushed or deployed.**

## Sources checked independently

- https://developers.openai.com/api/docs/models/gpt-realtime-2.1-mini.md
- https://developers.openai.com/api/docs/pricing
- https://developers.openai.com/api/docs/guides/voice-websockets?api=realtime
- https://developers.openai.com/api/docs/guides/realtime-conversations

The shared WebSocket guide contains GPT-Live and Realtime sections; this adapter was checked against the Realtime section, not Live's distinct session protocol.
