# Diktat: OpenAI preparation, not a release

Historical preparation record; superseded acceptance status: [one authorized live test, 2026-11-15](DICTATION-OPENAI-LIVE-ACCEPTANCE.md). One generation now succeeded; web/iOS-screen listening gates and latest-base integration remain open. No commit, push or deployment.

Original preparation status: isolated, keyless integration candidate. At preparation time no live OpenAI request, secret entry, publication, commit, push or production deployment had been performed. The owner approved **at most USD 10/month**; approval of that ceiling does not supply a credential or authorize a live acceptance call. Live speech fidelity, account/model access, latency, invoice usage and native/browser playback of this provider remain unverified.

## Isolation and preserved work

- Original candidate: `/Users/tinyserve/Projects/KeineMagie`, actual HEAD `df309d46d8760c61442220d10aac78049fe5e59c` (the stable-header implementation is `375b94e`). It was not reset, rebased or edited.
- Full private backup (including ignored files and Git metadata): `/Users/tinyserve/Projects/KeineMagie-backups/20261114T083302Z/candidate-full.tar.gz`.
- Archive SHA256: `bc843f39e9352259fedc7ad43af255597c3b5238392832827c71c7139ff2a2e1`. Treat the backup as private; do not publish it.
- Integration worktree: `/Users/tinyserve/Projects/KeineMagie-dictation-openai`, branch `candidate/dictation-openai`, based on `d99427b8dd9cf19fae2041066410c686e9d7ab0a`.
- Three-way port of the candidate tracked delta; manually combined AppModel reset and simulator-fixture additions with upstream outbox/catalog logic. Catalog merge retains every upstream key and value (including outbox keys); only Diktat entries are added. Flame artwork, existing web geometry, outbox storage and native catalog source stay on the newer base.
- Candidate Diktat source, historical acceptance docs and license evidence are retained. Legacy Piper adapter is test-only (`dictation_legacy_adapter_test.go`), with no production subprocess/socket selection. `server/dictation-tts` is excluded from the Docker context. Its historical worker artifacts are not a dependency of this release path, and no Piper distribution/source-bundle step is needed for this image.

## Independently checked official API documentation

Checked 2026-11-14:

1. [Text-to-speech guide](https://developers.openai.com/api/docs/guides/text-to-speech): `tts-1`, `tts-1-hd`, `gpt-4o-mini-tts` shut down January 6, 2027; recommends `gpt-realtime-2.1-mini` via Realtime, **not** `/v1/audio/speech`.
2. [Model](https://developers.openai.com/api/docs/models/gpt-realtime-2.1-mini): Realtime supported, Speech endpoint unsupported; 128,000 context, 32,000 maximum output tokens.
3. [WebSocket guide](https://developers.openai.com/api/docs/guides/voice-websockets?api=realtime): `wss://api.openai.com/v1/realtime?model=...`, server-side Bearer authorization. The shared guide also includes GPT-Live; do not substitute its `/v1/live/sessions` protocol.
4. [Conversations](https://developers.openai.com/api/docs/guides/realtime-conversations), [client events](https://developers.openai.com/api/reference/resources/realtime/client-events): GA `session.update`, `conversation.item.create`, `response.create`; audio emits `response.output_audio.delta`, audio transcript events and `response.done`. No beta header. Instructions are **not guaranteed** to be followed.
5. [Pricing](https://developers.openai.com/api/docs/pricing): USD per million tokens, text input **$0.60**, cached text input **$0.06**, text output **$2.40**, audio input **$10**, cached audio input **$0.30**, audio output **$20**. These are not the deprecated TTS per-character/per-minute prices.
6. [Cost guide](https://developers.openai.com/api/docs/guides/voice-latency-cost?api=realtime): Realtime assistant audio is approximately one token/50 ms, plus special tokens; text and audio both contribute. Provider prefix caching is not our asset cache.
7. [Project administration](https://help.openai.com/articles/9186755): project-scoped service accounts/keys and limits. Dashboard controls evolve; do not assume a budget/alert is a hard cutoff. This candidate does not rely on any dashboard spending control.

Voices accepted by this adapter are the documented built-ins: alloy, ash, ballad, coral, echo, sage, shimmer, verse, marin, cedar. Example uses marin. Custom voices are not enabled. Realtime formats include PCM 24 kHz, G.711 μ-law and A-law; this integration explicitly requests mono PCM16 at 24 kHz and wraps the completed stream in WAV. It does not request MP3 from Realtime or invent word timestamps.

## Exact source and audio contract

- Only an authenticated, CSRF-protected (web) explicit Prepare POST generates. Loading, GET, Range, replay, speed changes, writing and grading never generate.
- Each whole-text, sentence or meaningful clause asset gets a fresh one-response WebSocket; repeated identical plan segments share one asset. No automatic paid retries or model/provider fallback.
- Source text is sent as data, unchanged. Fixed instructions request neutral German verbatim narration, ignoring embedded instructions, questions and commands. Tools and turn detection are disabled; no microphone input.
- Audio stays server-side until complete. Require the same response/item identity, audio completion, completed response and generated transcript. Compare Unicode-NFC lexical tokens in order, case-insensitively; ignore punctuation/spacing, but **never** omit/add/reorder words, paraphrase, expand numbers or modify the stored source. Mismatch, refusal, missing transcript, incomplete response and overflow fail closed without publishing audio.
- This checks the model's output transcript, **not an independent acoustic transcription**. It is a necessary gate, not proof the sound exactly matches. Abbreviations/numbers may fail conservatively. Real German listening acceptance is still required; do not silently rewrite text to improve success.
- Deadline, frame/event/output-token/PCM-byte limits; disconnect/cancellation closes the socket. Best-effort response cancellation is not a billing refund or proof remote generation stopped immediately.
- Existing owner-scoped atomic private assets, durable drafts/attempts/deletion tombstones, authenticated HTTP Range, logout/publication fences and native AVAudioPlayer remain. No public media URLs or browser/native provider key.

## USD 10/month guard — deliberately conservative

A cross-process locked, fsynced global ledger at `dictations/paid-months/YYYY-MM.json` reserves **USD 1 per uncached generation attempt**, before sending. Maximum **10 attempts per UTC calendar month**, shared by all app users and every backend sharing the same persistent data directory. Historical monthly ledgers remain; restarting does not reset them.

Why $1: at the checked rates, the *entire documented model envelope*, even ignoring our smaller input limit, is `128000 × $0.60/1M + 32000 × $20/1M = $0.7168`. This pessimistically prices every output token at the most expensive output modality and leaves $0.2832 margin. Actual sessions also cap output at no more than 4096 tokens and source at 1800 characters. No tools, image or audio input are sent. A 10-attempt month therefore has a documented-rate model-envelope estimate of $7.168, below the approved $10.

**This is not an unconditional OpenAI invoice cap.** It assumes the published model/token bounds and rates, excludes taxes, exchange rates, other applications/project users, out-of-band calls and billing posting-month differences. Unknown pricing changes cannot be bounded honestly. Use a dedicated project/key, recheck prices/model limits before enabling and each month, and disable generation if they change. Never claim dashboard soft alerts enforce this budget.

`response.done.usage` is recorded privately with integer micro-dollar accounting for input/output text/audio; input cache discounts are ignored conservatively. Unknown, missing or malformed usage keeps the full hold. **Even valid actual usage does not automatically refund the $1 reservation** in this cautious candidate. Cancellation, socket loss, mismatch, crash before/after send and failed publication retain holds; explicit retry consumes another one. This sacrifices throughput to avoid optimistic reconciliation/double-billing claims. External exactly-once generation is impossible to guarantee. No operator should edit/reset the ledger to recover holds without a separately reviewed invoice reconciliation.

Additional durable global daily request/character/full-duration reservations apply. The full configured duration is reserved for every attempt and never refunded, even if actual audio is shorter. One cross-process nonblocking generation slot; busy returns 429, not an unbounded server wait queue. Clients retain their explicit serial preparation behavior. Cache GET and cached Prepare bypass all paid reservations. Per-owner legacy daily request ceiling remains an additional bound.

Example limits are in `server/dictation-openai.env.example`; provider is deliberately blank. Enabling with missing/invalid limits or missing dedicated key fails closed. Unsupported model/voice or concurrency other than one fails closed. No ambient `OPENAI_API_KEY`, Hermes key, native Keychain or ChatGPT OAuth credential is consulted.

## Secure owner-operated key entry (does not activate anything)

Create a dedicated project-scoped service-account/API key in the owner's billed OpenAI project, restricted to required Realtime/model access where available. Do not use an organization/admin key. Do not paste any key in chat, a command argument, Git, CI variables/logs, browser storage, native preferences or a support screenshot.

The owner can run this locally in their own terminal:

```sh
python3 /Users/tinyserve/Projects/KeineMagie-dictation-openai/scripts/setup_dictation_openai_key.py
```

It uses a hidden TTY prompt, writes exclusively to:

`/Users/tinyserve/.config/keinemagie/secrets/dictation-openai.key`

The new file is mode 0600 in a 0700 directory, rejects symlink paths and existing-file overwrite, fsyncs file/directory, prints no secret and makes no API request. Only synthetic file-write tests have run; the real destination has not been read or populated by this work.

For a later approved deployment, copy/install the file through the deployment host's secure secret mechanism, mount it **read-only** at `/run/secrets/dictation-openai.key`, readable only by the backend UID 65532. Docker Desktop bind permissions must be checked without displaying the key; never make it world-readable to work around a permission problem. Keep the whole `HISTORY_PATH` parent persistent: it contains private assets, daily and monthly admission ledgers. Backends sharing this project must share that store; a second independent store defeats the global budget. Do not change active production mounts during this preparation.

Set `DICTATION_OPENAI_API_KEY_FILE` to the mounted path. A process-local `DICTATION_OPENAI_API_KEY` environment variable is supported only as an explicit alternative (never both); prefer mounted secrets because environment inspection can expose values. Never configure a global Hermes key. The app clients receive only authenticated WAV bytes and safe errors.

## Recorded local verification

- `go test -race ./...` and `go vet ./...`: pass. Focused Diktat race suite also passes after the final cancellation/busy test. Monthly tests launch concurrent child processes, SIGKILL one after reservation, and confirm only the remaining nine admissions succeed.
- `node --test web/tests/*.test.mjs`: **94 passed**.
- `swift test`: **36 XCTest + 68 Swift Testing passed**.
- Native CI: **50 tests, one intentional skip**, plus **43 executable AppModel lifecycle tests passed**. The port initially exposed missing/non-localizable Diktat UI literals; fixed without removing any upstream localization entry.
- Fresh Xcode Debug simulator build: exit 0; this is compilation, not new provider playback evidence.
- Secret writer: **2 synthetic local filesystem tests passed**; no real key read or written.
- Verified original tracked candidate delta unchanged, **265 upstream localization entries and all 20 outbox keys unchanged**, protected web stylesheet/favicon/outbox source unchanged from integration base.
- Native Prepare timeout explicitly exceeds the bounded server generation timeout; cached reads retain their original shorter timeout.

## Acceptance gates

Already exercised locally:
- Go race tests and vet; synthetic WebSocket/PCM tests for verbatim transcript matching, request/session shape, cancellation and no auto-retry.
- Persistent daily/monthly admission, conservative usage accounting, cache/no-new-call and uncertain failure/no-refund tests; existing private Range/owner/logout/draft/attempt tests.
- Web Node suite, Swift Core tests, executable AppModel lifecycle tests (including newer outbox/catalog), localization checks, fresh Debug simulator app build.
- Real distroless image build and restricted read-only/nonroot/keyless local container: health 200, protected Diktat 401. Final local image `keinemagie-dictation-openai:local-prep`, ID `sha256:6355b48f3637ee111c7f48b8ad9a51767027628f8d55ac54145c48624bb511e0`. Probe container removed. No Python/Piper runtime or provider credential supplied.

Still blocked before release:
1. Owner manually configures the dedicated key; explicit limited live-test consent remains required.
2. Check model access/rates, real GA event shape and usage schema with one short German source; then verify transcript gate and listen on both web/native. The synthetic tests are not speech-quality or paid-billing evidence.
3. Verify real cancellation/uncertainty under agreed limits, persistent deployment volume/secret permissions and precise invoice reconciliation; test final release build/UI geometry as required.
4. Separate approval to commit/push/publish/deploy. No release action is authorized by this document.
