# Combined Dictation and translation release — 2026-11-19

**Web/backend live; iOS 1.0 (2789.91.59) uploaded successfully to Apple.** Exact product source: `a6699b034eb4584c533a6c2268ea35bafd040a2f`. Apple processing, tester availability and physical installation are separate, unverified gates.

## Integrated source

Fresh origin/main was `c0c6ff3be9194495e45abe921181b403da0c3542`. Dedicated clean worktree: `/Users/tinyserve/Projects/KeineMagie-combined-release`, branch `release/combined-dictation-20261119`. Normal non-force `HEAD:main` push and remote readback were verified; the owner's dirty main was not checked out/reset.

- Native camera/back navigation, global minimal player and durable Stop: `6cbfb1cf891d8302178e19cfaa918cb737299bdd` (all six candidate commits retained).
- Web spacious cards, word count/decoded duration and authoritative four-stage lifecycle: `dfb3dc729d5f29a6afcb711ae0e6dd2aba9b8578` (both candidate commits retained).
- Native feature-specific translation transport deadlines, eight-second authentication deadlines: `f8834451407b1c5cbbbbe8c900aa8407bd0ec9cf`, cherry-picked as `80d8f59011720a5b5045902715fb1024ea577675` after merge `25790cc`.
- Independently reviewed lost-ack Stop correction: `a6699b034eb4584c533a6c2268ea35bafd040a2f`.

The only merge conflict was the comment preceding the identical canceled-before-admission context guard. One guard and the complete Stop ledger remain. Both native catalogs remain byte-identical to the native candidate; no key/locale was regenerated or dropped.

## Independent review correction

Initial combined review found that a committed start/progress whose acknowledgment is lost could leave a durable Stop retrying an obsolete fence forever. Real Go and Swift-controller/Go cold-journal regressions failed before correction.

The server now persists `stop_base`, the revision before the active admission's current ownership began. A named Stop may bridge lost acknowledgments only for that exact admission/client within its uninterrupted ownership interval. Every resume establishes a new boundary, so a foreign takeover—even followed by return to the former client—does not permit an old Stop. Legacy reservations without the field retain strict revision checks. The native controller retains the last acknowledged owned admission identity after interruption. No quota refund, final-reading restoration, authentication weakening or refresh-based fence adoption occurs.

The real bridge checks lost start and progress responses, offline Stop, cold journal restore, successful Check/mode cancellation path, unchanged spent start, then explicit zero-based new playback. Go tests additionally cover handler recreation, idempotent recovery and foreign ownership rejection. A second independent read-only review passed this four-file fix. Suggested extra legacy/lost-resume boundary tests remain nonblocking, not claimed as executed.

**Recovery compatibility:** pre-Stop binaries discard durable Stop fields; even the prior native candidate lacks `stop_base`. The deployed writer is pinned as the only recovery target. Never restart an older typed writer or restore historical user data/budget holds. The saved previous override is forensic only.

## Final executed gates

Evidence root: `/Users/tinyserve/.hermes/cache/scratch/combined-release-20261119/`. Sanitized durable receipt: `combined-dictation-translation-receipt.json` alongside this document.

| Gate | Result and scope |
|---|---|
| Full Go race after correction | PASS, 90.288s (`go-race-fix.log`) |
| Full Go vet after correction | PASS (`go-vet-fix.log`) |
| Native CI discovery after correction | 64 reported, 1 built-plist skip; 119 actual AppModel lifecycle tests passed |
| Swift Core after correction | 100 XCTest reported, 4 opt-in fixture skips, no failures; 84 Swift Testing passed, including delayed-HTTP deadline regression |
| Actual Swift controller → Go bridge | 3 passed, no skips; cold lost-ack recovery and Stop/four-start contract |
| Final exact-source Node | 166 passed, 1 opt-in wire skip (`node-final.log`); profile real-Go wire/browser gate independently passed |
| Real Apple Vision harness | Six groups passed; generated printed image, not physical camera/handwriting |
| Final exact-source Chromium/Go lifecycle | 30 locale/theme/width cases; zero library media/mutation calls; screenshot inspected |
| Final Chromium/Go playback policy | PASS; actual media pipeline with synthetic WAV, no provider |
| Coherent normal Release UI | **13 passed, 0 failed, 0 skipped**, exit 0; readable `normal-retry.xcresult` |
| Serial focused SE Release UI | **5 passed, 0 failed, 0 skipped**, exit 0; readable `small.xcresult` |
| Hosted push validation | Run `44590575526`, success |
| Hosted publication validation | Job `135801654560`, success; actual archive/export/upload followed |

The earlier tool approval hold was resolved by fresh explicit user approval; the parent actually started the normal run. No approval bypass or policy/configuration change occurred. That running process was monitored, not duplicated. Normal covered all nine requested player/camera tests plus TranslationDeadline and all three TranslationOutbox tests. SE repeated camera, off-tab Stop/reset, long localized accessibility player, real deadline, and offline outbox relaunch/retry. Existing UUIDs only: normal `93E1113F-6736-4CCB-827D-0E2F1C3876EA`, SE `56A70197-59DE-4410-9E76-25272244E9C8`; serial/no cloning, both shut down afterward. The native fixture remained available through both suites and expired naturally afterward. Actual history count was checked before the SE batch; no production cap was changed.

Initial final-source web fixture correctly rejected browser writes because the new loopback port lacked matching `WEB_ORIGIN`. Only the isolated fixture environment was corrected, and the entire lifecycle/policy sequence reran successfully. No production origin/auth rule was weakened.

## Server publication and deployment

- Server-image CI **44590575523**, job **135795156730**, exact source SHA, success; Build image publication step verified.
- Pulled registry artifact `ghcr.io/ptmt/diktat-server:sha-a6699b0`; local image ID and repository digest: **`sha256:fdff5214c556b8e2bd55b3a406f8f5264990e7b4f6a70ed8207eba1bad2d7a82`**. ARM64 and exact OCI revision verified.
- Existing tinyserve Compose base + durable override applied **backend only**. The service registry still names `keinemagie:local`; this remains the established manual Compose lifecycle, not automatic tinyserve registry deployment. Do not run a blind tinyserve deploy that discards the private-worker override.
- Nonblocking durable store/account locks, idle-state revalidation, backend stop, released global runner flock and private backup precede replacement. All **41 nonruntime persisted files byte-identical** afterward. **1 completed podcast, 2113 segments and translations**, no active jobs.
- Worker image `sha256:a61794a3d7e74b63d9626c453f3b0bac1b9f9f1351b0bb6349ccf564bded9382`, worker/unrelated container IDs, environment, quota configuration, resources/security, mounts/secrets and network membership preserved. Backend retains `tinyserve_edge` and `tinyserve_podcast_private`; private network remains exactly backend + worker.
- Private backup/recovery directory: `/Users/tinyserve/Library/Application Support/tinyserve/services/keinemagie/deployment/release-combined-20261119T184448Z/`. `compose.policy-safe-recovery.yml` pins this stop_base-aware image; `RECOVERY.txt` explicitly forbids old-writer rollback and historical-data restoration.

The first preflight safely stopped **before changing the running backend** because an old one-entry budget assertion was stale. Fresh read-only aggregate inspection showed **two preexisting November entries, USD 2 reserved, 20111 micro-USD reported cost**. The exact current assertion was then revalidated under locks and both entries preserved unchanged. The USD 10 application cap is unchanged; at most **eight** additional USD 1 reservations remain under this snapshot, not the earlier nine. Deployment made no paid call and did not create this second historical entry.

## Public HTTPS and real web rendering

Certificate-validated IPv4 HTTPS `https://keinemagie.tinyserve.org/health` returned **200**; `/v1/web/session`, `/v1/podcasts` and `/v1/learning/dictations` returned **401** without credentials. All **31** public assets derived from the Dockerfile allowlist returned **200/no-store** and exact committed bytes.

Actual live HTTPS modules passed all **30** lifecycle presentation cases with every private API intercepted before bootstrap and routed only to isolated synthetic Go storage. No private request escaped, no library media or mutation occurred. This proves shipped rendering/contracts, not signed-in production inference. Real guest bootstrap separately had zero JS errors, zero mutations and no private cards.

Retained actual screenshots under `docs/evidence/combined-release/`: live RU dark 390px cards, normal native minimal player, SE accessibility player, and guest web. These are unmodified runtime captures, not recreated UI.

## Apple delivery

Exactly one explicit `publish=UPLOAD` dispatch after backend/live verification:

- Run **44591241250**, exact `a6699b034eb4584c533a6c2268ea35bafd040a2f`, **success**.
- Validate job **135801654560**; TestFlight job **135805494659**, both **success**. Signing-material cleanup step successful.
- Marketing version **1.0**, build **2789.91.59**.
- Actual Apple output at **2026-11-19 19:04:42Z**: **`UPLOAD SUCCEEDED with no errors, 1 warning`**.
- Warning **90725** announces the future April 2027 iOS 27 SDK requirement; this accepted archive used the existing hosted iOS 26.5 SDK/Xcode 26.6 workflow. No signing or toolchain change was made to this release. Upgrade the hosted SDK before that future deadline.

Uploaded is not processed, available to testers, or installed. No App Store review submission was made.

## Preservation and limits

Original KeineMagie **304** protected dirty-file hashes/exact expanded status and AnyProgress (`Projects/anyring`) **13** files/status were verified unchanged. No owner cookies/provider credentials were copied; no real AI/TTS, outbox replay, request clearing, quota reset, or user-content write occurred.

The timeout repair does not resurrect the old uncertain translation. Keep it intact; Check result is GET-only. A genuinely new paid attempt requires the user's explicit informed decision. Physical camera/permission denial/handwriting and spoken VoiceOver remain unverified. Native runs retained AVAudioSession main-thread and system gravity-well runtime warnings, with no failed assertions. Synthetic OCR/audio/HTTP do not establish physical capture or personal-provider quality.
