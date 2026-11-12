# Web podcast controls + inline history release — 2026-11-12

## Delivered

- Live: **https://keinemagie.tinyserve.org**. Source **`1c741960f284eebc81306f29569d69a1380335f8`**, pushed and read back on main. Exactly nine web implementation/test/documentation files; no native/server source changes. Concurrent native commits were preserved as parents; untracked `spikes/` excluded.
- Podcast feed title shown once, compact episode rows and prepared-title links; refresh/unsubscribe and confirmed delete use accessible native disclosures (Enter, Escape/focus return, outside click). Five locales, keyed pending/menu state and existing owner/CSRF contracts preserved. No automatic AI.
- Saved history shows the **entire exact translation immediately**, below muted source: textContent, pre-wrap, language attributes, no truncation/entity conversion. Reopen/copy behavior unchanged.
- Existing actual independent Astra before/after review is recorded in `web/REDESIGN-VERIFICATION.md`: exact `openai/gpt-6-astra`, max, no fallback; populated synthetic desktop/mobile inspected. No additional paid review or production inference performed for release.

## Verification

- Independent release source/security review: no blocking findings. Added 1,200-line Unicode/literal markup/entity/leading-and-trailing-whitespace regression, exact textContent before/after locale/reopen. Node **61/61**, three release browser suites (podcast design, history, five-locale HTTP) passed without page errors; Go test and vet passed. Implementation's prior **16-browser-suite** pass is recorded separately, not misrepresented as a fresh full release rerun.
- Server image workflow **[43200451788](https://github.com/ptmt/KeineMagie/actions/runs/43200451788)** at exact source completed **success**, Build image success. Registry publication is separate from the established manual Compose deployment. Web-only paths do not trigger iOS TestFlight; no native upload claimed for this release.
- Actual public TLS `/health` **200**; **all 16 assets byte-for-byte and SHA-256 equal clean committed source**. CSP/no-store retained. Four protected guest reads **401**, four private/nonallowlisted paths **404**, nested reader shell **200**.
- Actual deployed Chromium guest at **390/1440**: new Refresh list label, private add disabled, empty private lists, no overflow/page errors. Mobile screenshot inspected. No credentials/cookies replayed, no synthetic interception on production. Signed-in history/feed behavior is fixture-tested, not claimed as private production verification.

## Backend-only replacement and safety

- Deployed image **`sha256:9ef529a10664ea81f1915aca9303595782a203c460cef23e1bedf8c96d62d2fd`**, revision label exact source above. Built from clean `git archive`, network-disabled build steps. Executable unchanged versus prior image: SHA-256 **`78c71317f86c2b453f435c27038cd11d62f733117be0063b709460a7ccc72658`**.
- Only backend image pin changed in complete merged base + durable override. Resources, env, mounts, routing labels and networks verified equal. Worker **`sha256:a61794a3d7e74b63d9626c453f3b0bac1b9f9f1351b0bb6349ccf564bded9382`** and all unrelated container IDs retained.
- Held nonblocking store/account locks, revalidated idle, stopped only backend, acquired released lifetime runner flock, backed up six volumes privately excluding runtime locks, released runner immediately before replacement and retained store locks through final snapshot.
- **Seven nonruntime data files unchanged**; aggregate **1 completed job / 1 subscription / 2113 segments / 2113 translations / zero active jobs** unchanged. No transcript/account contents printed. No retries, resets, new jobs or provider calls.
- Backup/rollback configuration: `deployment/release-podcast-design-20261112T102806Z/` under service deployment (0700 directory, 0600 files). Rollback `compose.previous.yml` pins prior backend `e3e1302d9795…`; use original base plus that override with backend-only `up -d --no-deps --pull never keinemagie`. Never restore historical data for binary rollback. Rollback prepared, not exercised.
- Lifecycle caveat retained: tinyserve's local image registration does not automatically load the durable Compose override. This is the established explicit Compose lifecycle, not a claimed automatic registry deployment.

Evidence: scratch `podcast-design-evidence/`, `km-podcast-public-verified.json`, `km-podcast-live-guest.png`; private deployment `verified.json` contains provenance/config/data-count checks. Initial Python archive API incompatibility was corrected using system tar; urllib received HTTP 403, while curl and real Chromium verified public TLS successfully. Neither required production changes or weakened TLS/CSP.
