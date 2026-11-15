# Coach, quiet recovery and initial translator geometry

## Scope

Integration starts at `2c7bbe9bcde1a887e362a7c83a966e5538711222`, preserving
released Podcast null-array decoding and compact Coach. It includes reviewed
Coach `e75f7eb582a850b553b53f07180478413bce9712`, both quiet commits
`85b4455e67295920067b6e61aa60dbe978d6dbeb` and
`f181f96820dbe3aae3c659ecbc255054ae8295af`, then the UI-only initial-geometry patch.
Localization conflicts were semantically merged: all 20 existing outbox keys and
all released Podcast keys retained; 302 catalog keys have all five locales.
Flame artwork, exact personal Terra routing, and private recognition worker remain
unchanged. Pending Diktat/OpenAI TTS candidates and dirty main are not included.

Translator initial built-in style footprints are present before the module loads.
Provider diagnostics remain in account settings; history errors follow saved rows.
Native pending work is a compact toolbar disclosure, never a shifting form row.
Unknown translation receipts recover through authenticated GET history only.
Contextual Coach assessment persists the literal answer before POST and clears
owner-scoped Coach cache on logout. Synthetic `beim` assessment corrects to `bei`;
this does not establish real model quality.

## Combined verification

Evidence directory: `/Users/tinyserve/.hermes/cache/scratch/km-combined-release/`.

- Full uncached Go race suite with serial test scheduling: passed, 147.889 seconds;
  `go vet ./...` passed. No test removed or weakened.
- Node: 82 passed. Native CI: 51 checks, one pre-build metadata skip; actual
  AppModel harness: 61 passed before independent-review follow-up.
- Actual Go Podcast wire serialized and decoded in Swift: six shape tests passed,
  including null segments, server titles, strict malformed-data failures.
- Seven actual authenticated Go Coach snapshots decoded by production Swift DTOs.
- Browser initial geometry: 40 cases / 2068 checks, zero failures, five locales.
  Existing status geometry: 520 checks, plus synthetic Coach browser passed.
  Original 13 saved geometry comparisons: every measured delta exactly zero.
- Ad-hoc-signed Release iPhone 17/iOS 27.2 initial geometry: 4 passed, zero skips
  or xcresult runtime warnings. Five-locale provider/history settlement,
  keyboard/navigation, durable outbox restoration verified.
- Compiled app: all 122 Coach/outbox/Podcast-load feature labels and 20 Core labels
  verified in each of five real bundles. Signature and three effective metadata
  checks passed.

Initial local Core wrapper used the wrong toolchain and could not import XCTest;
full-Xcode `swift test` passed. The new Playwright browser runtime was installed.
The bootstrap test was corrected to read localized textContent of a mobile-hidden
header span; actual content was already Russian, while innerText was empty.
Status geometry retains its pre-existing pending-route cleanup warnings.

Independent review found and fixed a native unacknowledged-answer refresh-loss
path: cached request/prior-attempt identity now survives successful reads and cold
relaunch until the exact server acknowledgement or explicit cancel/reset. Explicit
recovery reuses the original request; no automatic inference/repost occurs. A
missing/reset server turn retains the literal answer but blocks an invalid retry.
Owner-scope fencing prevents cross-account merging. RED reproduced eight failing
assertions; new executable AppModel/Core regressions are retained.

The browser mutation counter now records every API method before endpoint holding;
an injected translation POST is detected. Fresh native CI passes 51 checks (one
pre-build metadata skip), including 66 actual AppModel cases. Core: 68 Swift Testing
and 29 XCTest cases, one opt-in wire skip subsequently executed by the six-test
actual-Go-wire run. Seven Coach wire snapshots pass. Sandbox-only loopback
failures from the independent fix agent were not weakened; normal local runs pass.
Independent re-review returned PASS with no actionable findings (82 Node and
17 native source checks). Final combined Release matrix passed geometry 4, quiet 9,
Podcast wire UI 2, outbox 3 and catalog 2; the single Coach fixture failure in the
27-test combined run was repaired as documented below, then the entire seven-test
Coach suite passed. Final dark/reduced-motion subset: 3 passed. No skips or xcresult
runtime warnings. All original 13 geometry deltas remained exactly zero.

The rebuilt UI matrix exposed a simulator contract bug: its hardcoded attempt ID
was not the submitted request ID, so correct receipt reconciliation retained both
records and the profile test found duplicate review buttons. The simulator-only
fixture now echoes `action.requestID`, matching actual Go answer/skip handlers;
independent review passed. No production matching rule or UI assertion was weakened.

## Deployment invariants

Backend first, through the established manual Compose base plus durable override,
not a claim that normal tinyserve deployment handles the local image. Preserve
`--providers.docker.network=tinyserve_edge` in the durable Traefik command.
Only the backend image pin may change; worker image, IDs, mounts, resource limits,
private network and all unrelated containers remain unchanged. Take store-locked
private backups while idle; never restore old data for a binary rollback.
Preflight public HTTPS health 200, worker authenticated readiness 200 and
unauthenticated readiness 401 passed. No provider inference or credentials logged.
Hostname remains `keinemagie.tinyserve.org`; no domain migration.

After deployment/readback, dispatch exactly one main iOS workflow with
`publish=UPLOAD`; bind run/jobs/build number and Apple upload result to its full SHA.
Apple upload success is distinct from processing, tester availability and device
installation. No real provider grading-quality claim is made.

## Backend publication readback

- Published source: `1bf7be2a8e6ee220c5d3e08cfeb698d6da1920d7`.
  Backend image `sha256:e3f948148768c4938682e48ecee29397226398864f117e8054e9212adfe9de57`.
- Server CI: https://github.com/ptmt/KeineMagie/actions/runs/43714092957 — success.
  Local pinned arm64 image uses the established Compose lifecycle; GHCR build
  publication is separate from this host deployment.
- Worker unchanged: `sha256:a61794a3d7e74b63d9626c453f3b0bac1b9f9f1351b0bb6349ccf564bded9382`.
  Worker and all unrelated container IDs unchanged; full merged Compose changed
  only backend image. Resource/mount/routing/private-network checks passed,
  including the reboot Traefik `tinyserve_edge` provider-network fix.
- Actual locked snapshot: **11** non-runtime durable files, all byte-identical;
  **1 completed job, 0 active, 1 subscription, 2113 segments and 2113 translations**;
  **1 user, 3 sessions**. These supersede earlier nine-file/partial-job assumptions.
- Private six-volume backup:
  `deployment/release-coach-quiet-geometry-20261115T122924Z/`, mode 0700/0600.
  Backup values and credentials were not printed. Rollback uses its prior image
  and current data, never historical data restoration.
- Public certificate-valid HTTPS health **200**; session/Podcast/Coach **401**.
  Legacy no-bearer translations intentionally **503** with shared TTS disabled;
  correctly shaped invalid native bearer **401**. All responses no-store.
- Seven public assets matched committed bytes/SHA256; real production Chromium
  verified five locales, guest locks, empty private history, stable navigation,
  and zero mutations. Worker authenticated readiness **200**, unauthenticated **401**;
  final private membership exactly backend and worker.
- Initial post-replacement inspector rejected Docker DNS `[]` versus `null` and
  reordered binds; exact diff inspection and canonical comparison passed without
  redeployment. No configuration value changed.

## iOS publication

Initial push validation and first explicit-upload validation lacked Go on the
hosted macOS runner; both failed before signing/upload. Workflow-only follow-up
`2969bcb5137a13846ada5992bed28e8962d3e8d2` pins setup-go and installs Go 1.27.4
before actual server-to-Swift tests. Native/backend/web sources are byte-identical
to the deployed release. Apple run:
https://github.com/ptmt/KeineMagie/actions/runs/43714338763 — **success** at exact
SHA `2969bcb5137a13846ada5992bed28e8962d3e8d2`. Validation job `132813575609`,
upload job `132814478263`; signed archive and export succeeded. Version **1.0**,
build **2753.8.10**, Apple **`UPLOAD SUCCEEDED with no errors`** at
**2026-11-15T12:44:13.8846370Z**. Signing cleanup succeeded. No duplicate accepted
package was dispatched: the earlier explicit run failed before signing.
App Store processing, tester assignment and physical iPhone installation remain
unverified. CI-only follow-up does not require another backend replacement.

Obsidian initially returned empty reads/resource-deadlock for its iCloud placeholder.
A targeted `brctl download` hydrated the existing note; the current release and
nearest device checks were updated minimally without overwriting unseen content.
