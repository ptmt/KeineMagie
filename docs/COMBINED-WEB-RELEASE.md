# Combined web/server release — 2026-11-12

Live: **https://keinemagie.tinyserve.org**.

## Delivered

- Source **`8eb6d08dd7935540c45ee7f7f0334cdb3b98935a`**, explicitly staged 33 intended server/web/test/documentation files, pushed to `main` and remote SHA read back. No native/workflow edits; untracked spikes and Python caches excluded.
- Saved-translation clarification threads, explicit suggested-revision application, retry idempotency and revocation-safe persistence. Original history stays unchanged. Episode sticky section navigation, bounded transcript find/jump/citation return, and owner-scoped CEFR learning settings in Profile. Five interface languages.
- Built **from a clean `git archive` of that source**, not the working tree. Backend image **`sha256:60fde672735cb848a0816e8067420c8cb6752d8ff3d4809ea68b26a5b9833db3`**; OCI revision matches full source SHA. Exactly 18 public runtime assets copied, including both follow-up files.
- [Server CI 43211016183](https://github.com/ptmt/KeineMagie/actions/runs/43211016183): exact source SHA, **completed/success**; build/image-publication step success. The host uses its separately built local Apple Silicon image, not the registry artifact.

## Verification

- Integrated **Go race passed (36.557s)** and vet passed; **67 Node tests** passed. Follow-up Chromium **19 checks**; independent episode review **83 synthetic requests**, navigation **31**, reader **70**, analysis **7 checks**, HTTP i18n **24**, clipboard **22**. History preview, redesign, podcast design, bootstrap, light/dark visual suites and all seven legacy browser suites passed. All inference/API fixtures are synthetic, with no paid credentials.
- Reviewed final auth → owner-history lock order: no reverse history → auth callback, no provider HTTP under global auth lock. Existing revocation/concurrent-history regression tests pass with race detector.
- Public validated TLS `/health` **200**, all **18 assets exact committed bytes/SHA-256**. CSP remains strict self-only, no unsafe-inline/eval. Existing cache policy retained.
- Guest GET session/podcasts/subscriptions/vocabulary/both profile languages/follow-ups and empty unauthenticated POST follow-ups **401**. Source/env/test/history paths **404**. Nested private episode URL returns public shell **200**, never private content.
- Actual public Chromium: **RU/EN/DE × 320/390/768/1440**; locked translation/private controls, all four global routes contained, no horizontal overflow, new follow-up module/CSS loaded, nested episode protected, zero page errors or failed requests.
- Test-only issues: independent review initially asserted focus after a fixed 100ms before asynchronous deep-link restoration; immediate rerun passed, and the committed test now waits for the exact focused segment. Public test initially switched locale before artwork loaded, canceling its prior image request; awaiting image completion made the complete public run pass. No production workaround or CSP weakening.

## Backend-only deployment and preservation

Established original Compose base plus durable `deployment/compose.translator.yml`; full merged configuration compared privately and **only backend image changed**. This is the documented explicit Compose workaround, not automatic tinyserve registry deployment. Only `keinemagie` was stopped/recreated, using `up -d --no-deps --pull never keinemagie`.

Nonblocking durable store/account-active locks verified idle before stopping; lifetime runner lock acquired only after stop. Backups taken under locks, runner lock released immediately before startup, store locks retained through final snapshot. **Seven nonruntime files byte-identical**: auth/accounts, provider connection, history and jobs preserved. Authoritative before/after **1 completed job / 1 subscription / 2113 segments / 2113 translations / zero active jobs**. No retry, reset, new AI job or dummy follow-up appended.

Worker **`sha256:a61794a3d7e74b63d9626c453f3b0bac1b9f9f1351b0bb6349ccf564bded9382`** and its container ID unchanged, as were every unrelated container ID. Backend environment, routing labels, mounts, host/security/resources, networks preserved; private network exactly backend + worker. Global config, secrets and app ownership untouched.

Private backup **`deployment/release-combined-web-20261112T114041Z/`** under the existing service directory (0700 directory / 0600 artifacts). Contains prior Compose override, six volume archives and private before/after verification. Rollback uses `compose.previous.yml` with the original base, backend-only command, prior backend `9ef529a10664…`; preserve current data/worker, never restore old account data merely for binary rollback. Prepared, not destructively exercised.

## Limits

Live owner authentication, private saved-episode semantics and real personal-provider follow-up answer quality were **not exercised**. Synthetic tests establish rendering, API/security/storage contracts, not paid model quality. No new iOS build: existing TestFlight **2726.31.95** unchanged; this source's path filters triggered only server CI. Physical-device installation/processing remain separate gates.

Local detailed evidence: scratch `km-combined-public-verified.json`, clean archive `km-combined-release-8eb6d08/`; durable private deployment evidence `verified.json`, `containers.before.json`, `containers.after.json` in the backup directory.

## Follow-up textarea autogrow follow-up — 2026-11-12

- Source **`6f2c87cdc6a5719b7cd85ba6a8335cd7fed85a29`**, pushed and remote read back. Only follow-up module/CSS/browser test and its verification document; no server/native changes. Separate concurrent work and existing untracked spikes/caches excluded from staging and the clean committed archive.
- Native content sizing with three-line minimum and `min(50dvh,20rem)` cap; measured older-Safari fallback handles shrink, width/viewport changes, fonts and disclosure restoration without replacing the focused textarea. Character validation/API/safety unchanged. **67 Node tests**, **31 Chromium checks native + 31 forced fallback**, and **31 checks against actual public HTTPS assets with synthetic API interception** all passed. No paid inference or production fixture writes.
- Clean-archive backend image **`sha256:2a822d7ea44d44994b6cf5db298130129857e372caa72ed49c02930f05faa971`**, OCI revision exact. Backend executable byte-identical to previous image (SHA-256 `6eaeffbafec277d6a7d8c109105c6f39832dfacefde00e49ebd2cae6f3c3b3b5`). [Server CI 43213650240](https://github.com/ptmt/KeineMagie/actions/runs/43213650240) exact source **completed/success**, including image publication; host retains documented local-image Compose workaround.
- Backend-only replacement using unchanged original base/override, merged config image-only diff, idle store/account locks and private locked backups. **Seven nonruntime hashes unchanged; 1 completed job / 1 subscription / 2113 segments / 2113 translations**, no active jobs. Worker image/container and all unrelated container IDs, environment/resources/mounts/networks/routing labels unchanged. Backup `deployment/release-followup-autogrow-20261112T115854Z/`; previous image `60fde672735c…`, rollback configuration retained without restoring old user data.
- Public validated TLS health **200**, **18/18 assets byte-exact**, guest protected routes **401**, source/data paths **404**; actual public guest Chromium RU/EN/DE × 320/390/768/1440, zero errors/failed requests. Initial post-replacement public probes returned 504 while Traefik briefly chose the backend's private-network address; direct edge backend/proxy probes returned 200 and public routing converged without configuration changes. Final full public verification passed.
- Narrow 154-character draft screenshot `scratch/followup-autogrow-320.png` shows all text, counter and Send without clipping. Evidence: scratch `km-autogrow-public-verified.json`, clean `km-autogrow-release-6f2c87c/`, deployment `verified.json`. Independent CLI review attempts were blocked by missing Claude login and unsupported Codex account models; no review approval is claimed. Native/TestFlight unchanged.
