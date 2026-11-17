# Integrated web + iOS release — November 17, 2026

## Delivered scope and source

Translation profile synchronization, Coach/Daily, saved passage groups, Translator result/history controls, and focused Dictation playback now ship together. Native Dictation follows the reviewed web hierarchy: compact mode selector, untitled rules, audio action/speed/info, top-right Check, blank draft, original in the existing ellipsis. Policy-aware playback retains four whole-text starts, continuous sentence/repeat sequences with three-second writing pauses and a separate explicit final reading. No additional design or feature changes were made during release.

Reviewed candidate **`490656c334d4ddd6ee6172c10850c0bfda5858dc`**, final application-source change **`04e84f61096d3bcc7b63ad0866776eb2d0a10341`**. Fetch showed remote `e8ed89e95d6d4bd2eef01419ab52b76dd354d9f6` was not an ancestor: its only exclusive commit recorded the prior Translator release. Those exact documentation contents were already present in the reviewed tree. A normal merge produced **`78e2ebf589cbee9f574b497892319afa255de121`**, with **zero tree difference** versus the reviewed candidate (`git diff --exit-code` passed). That merge SHA was normally, non-force pushed from the clean release worktree and read back as remote main. Original dirty main was never checked out/reset.

Both image publication and Apple upload use **`78e2ebf589cbee9f574b497892319afa255de121`**. Any subsequent release-evidence commit is documentation-only, not another application build.

## Web/backend delivery

- Server workflow **44174908371**, build job **134363559541**: success, completed **2026-11-17T21:00:06Z**.
- GHCR image: `ghcr.io/ptmt/diktat-server:sha-78e2ebf`.
- Registry index digest and Docker-reported live image ID: **`sha256:c7ee5112434d3d133d3803d9a0f7e6ca7eb212062a2c467ff96dcc0f8a57f1cc`**.
- ARM64 platform manifest: **`sha256:9d8f3edf7c3aedc4e3e26ffbe7b17f9db925fc07cdf1a48f1198755592a324e2`**. Both ARM64 and AMD64 manifests are published. OCI revision equals the full release SHA.
- Live container **`f7c8e37ee74da65d9781dd73bd8ebbf26129d08252e9c8b5f37f502e69f40d1d`**, started **2026-11-17T21:01:09.829757208Z**.
- Established original Compose base plus durable `deployment/compose.translator.yml`; merged configuration changed **only the backend image**. This is the existing explicit Compose lifecycle, not an automatic tinyserve registry deploy. Backend-only `up -d --no-deps --pull never`; `tinyserve_edge`, routing, private worker network, resource/security settings, mounts and environment preserved.
- Worker image **`sha256:a61794a3d7e74b63d9626c453f3b0bac1b9f9f1351b0bb6349ccf564bded9382`**, worker and every unrelated container ID unchanged.

Under durable store/account locks, the backend was idle (one completed podcast job, zero active jobs). Stopped only the backend, acquired its released runner flock, backed up private data, released runner flock for replacement startup, and retained store/account locks through final readback. **All 30 nonruntime durable files byte-identical; 2113 segments and 2113 translations unchanged.** The single original paid acceptance entry, USD 1 reservation and 826 micro-USD reported cost remain unchanged. The USD 10 application monthly ceiling and maximum nine further November admissions are unchanged; no new paid operation occurred. Secret mount remains read-only, container UID/GID 65532 mode 0400/readable, host source mode 0600. Values were not printed.

Private evidence: `/Users/tinyserve/Library/Application Support/tinyserve/services/keinemagie/deployment/release-policy-integrated-20261117T210108Z/` (0700 directory / 0600 artifacts). Data archive SHA256 **`66b45e2f9e5a42ba2981bd7fdaa028a49c82bf94ddf5b481497c6be2b4fa9777`**.

### Mandatory policy-aware recovery boundary

**Do not use `compose.previous.yml` to roll back this release.** It is retained for forensic configuration comparison only. The old `b88118df4fce…` backend predates the playback ledger; its typed JSON rewrites can discard new persisted policy fields despite additive wire compatibility.

`compose.policy-safe-recovery.yml` pins the newly verified policy-aware image above and preserves current configuration/data. The deployment error handler likewise never reinstalls the old pre-policy binary. This is a safe exact-image restart/recovery target, **not a claim that an older functional rollback build exists or was tested**. If the new binary itself regresses, stop the backend and deploy a reviewed policy-preserving forward fix; do not restore historical data, remove budget holds, or run older field-dropping writers. Keep the private worker intact unless independently implicated.

## Public and browser verification

- Public TLS `/health` **200**, including a fresh successful read at **2026-11-17T21:18:14Z**. No certificate bypass or DNS override.
- **31/31** public runtime allowlisted assets match the exact committed release bytes and include `no-store`.
- Unauthenticated session, profiles, podcasts/subscriptions, Coach, Dictation and playback routes **401**. Source, `.env`, secret and ledger paths **404**. Existing GET `/v1/translations` remains fail-closed **503**, not falsely reported as 401.
- Actual Chromium public guest Dictation and Coach rendered correctly, without JS errors or mobile overflow; guest screenshot inspected.
- Live HTTPS Dictation modules/CSS with synthetic isolated data: **20** legacy/policy × mode × locale heading/disclosure cases passed; compact mobile/desktop screenshots inspected. Real Chromium audio suite passed four-start/fifth-denial, restart/recovery, same-reservation continuation, media failure, draft, sentence sequence/three-second pauses and final explicit reading checks, with **synthetic silent WAVs** and **13 Range requests**. Every private API was intercepted before bootstrap and handled by the isolated real Go fixture, not production accounts.
- Deployed asset-byte followup suite: **37** checks passed. Actual HTTPS tabs suite with every private API routed to local fixtures passed **10 locale/width cases**, keyboard/history/search/citations and zero AI POSTs.

Synthetic browser state is not real signed-in production acceptance. No owner credentials, real account mutations, live AI, new TTS, automatic retries or inference were used. Prior exact-source native acceptance is documented in `NATIVE-DICTATION-POLICY.md`: coherent **33/33** and small-device **6/6**, zero failures/skips. No local simulator was needed for this release; no simulator was created, cloned or deleted.

## iOS delivery

Push-only validation workflow **44174906917**, validate job **134363555677**: success; upload job intentionally skipped. This did not upload an app.

After backend deployment and public verification, exactly one explicit `publish=UPLOAD` dispatch was issued on unchanged main:

- Workflow **44175524773**, exact full release SHA: **success**, completed **2026-11-17T21:17:35Z**.
- Validate job **134367488008**: success, completed **21:10:46Z** (CI discovery, Swift Core, project generation, unsigned Release build, effective app metadata).
- Upload job **134371110906**: success; manual signing/archive/export/Apple validation/upload and cleanup passed.
- Marketing version **1.0** from the exact committed project; actual archive build **2773.42.65**, logged **21:11:28.5417980Z**.
- `ARCHIVE SUCCEEDED` **21:13:01.9663860Z**; `EXPORT SUCCEEDED` **21:13:05.5930180Z**.
- Apple archive validation: no errors, **21:16:14.2413620Z**.
- Apple **`UPLOAD SUCCEEDED with no errors` at 2026-11-17T21:17:26.6974790Z**.
- Cleanup step success, **21:17:27Z**.

Local watch calls timed out while the same remote job continued; the existing run was resumed/read back, never redispatched. No CI correction or application code change was necessary. Existing hosted warnings concern Node action runtime deprecation and runner capacity. Local Docker lacks `buildx`; standard `docker manifest inspect` successfully verified the published registry manifests.

**Uploaded is not processed or available to testers.** App Store Connect processing, tester availability and physical-device installation remain unverified; no App Review submission is claimed.

## Preservation and evidence

Original `/Users/tinyserve/Projects/KeineMagie`: all **304** preintegration file hashes match; exact expanded porcelain status matches, with **59** compact status entries. Unrelated AnyProgress source and all other worktrees were not edited.

Sanitized receipts and representative public/synthetic screenshots are under `docs/evidence/integrated-release/`; scratch verification is under `/Users/tinyserve/.hermes/cache/scratch/policy-integrated-release/`. Private container configurations, store snapshots and backups remain outside Git. The existing Obsidian app overview is updated separately after a successful full hydrated read.
