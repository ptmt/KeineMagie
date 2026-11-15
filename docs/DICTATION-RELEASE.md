# Diktat release — 2026-11-15

## Scope and authorization

Web and iOS Diktat, backed by owner-private Go storage and server-side OpenAI Realtime. Exact configured model `gpt-realtime-2.1-mini`, voice `marin`; no paid fallback, microphone recording, Piper runtime or new domain. The owner approved the already-generated short German voice sample («отлично») and a USD 10/month application ceiling. Release verification makes **no additional paid request**.

The release is based on `1c917c9e1ef2af116fd6b561acb649054846d3e1`. Parallel Coach chat work is excluded. Historical Piper source/provenance and the unrelated domain draft are not release payload. Original dirty main and its private backup are untouched.

## Behavior and security review

Authentication scopes records/assets to the hashed owner. Browser mutations retain exact-Origin/session-CSRF checks; private GET/Range requires identity and no-store. Draft mutations carry persisted identities/revisions, deletion tombstones prevent resurrection, and logout/owner changes fence late publication/playback. Generation is explicit Prepare only; opening, GET, cached Prepare/replay, grading and recovery never initiate paid inference. Realtime uses fixed server endpoint, bounded input/output/time/concurrency, completed response/item and lexical transcript checks. A model-generated transcript is not independent acoustic fidelity proof. Only the existing accepted short sample has human listening approval.

Durable global monthly admission reserves USD 1 permanently per uncached attempt, maximum ten per UTC month. Unknown/canceled/crashed/failed outcomes retain holds; no automatic retries/refunds. This assumes documented rates/model bounds, excludes taxes and other uses, and is not an unconditional invoice guarantee. The existing acceptance hold must be retained exactly once in production before enabling. The dedicated key is mounted read-only, UID 65532 mode 0400; host source stays 0600. No client or Git secret.

## Independently repeated gates

- 101 Node tests passed; Go focused Diktat race suite and vet passed.
- Actual Chromium accepted cached WAV: click-to-ended, repeat/pause/guided/draft reload/Check/new attempt/delete passed, no paid inference.
- Header browser regression passed after opening the already-released account dialog before its recovery button. No product assertion removed.
- Initial full race run exposed an existing signed-Apple test clock flake: frozen verifier versus wall-clock synthetic `iat` could cross a second under load. The test now signs on its frozen clock; 30 repeated race executions passed. Production authentication is unchanged.
- Integrated prior evidence: 50 XCTest (one skip), 68 Swift Testing, 69 executable AppModel checks, 53 native CI (one skip), six actual Go→Swift podcast wire tests; corrected Release Diktat UI 5/5 with real cached AVAudioPlayer completion. Existing Release regression suite passed 12/12 unaffected tests; earlier Diktat logout selector failure was corrected and rerun. Details: [integrated acceptance](DICTATION-INTEGRATED-ACCEPTANCE.md).

## Deployment and delivery evidence

Pending exact CI image publication, locked additive ledger migration, backend-only replacement, public verification and explicit `UPLOAD` workflow. Final evidence will be appended only after readback. Existing auth/history/podcast/Coach bytes must remain identical; only explicitly listed Diktat files may be added. Never restore stale data for binary rollback. Keep the supported tinyserve base plus durable Compose override (including `--providers.docker.network=tinyserve_edge`) and replace only backend image plus necessary Diktat environment/secret mount.
