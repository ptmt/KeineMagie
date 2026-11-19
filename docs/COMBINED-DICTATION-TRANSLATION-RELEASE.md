# Combined Dictation and translation release candidate — 2026-11-19

**Not published.** User authorization includes web/backend and iOS together. This is the integrated candidate and verification record, not evidence of deployment or Apple upload.

## Integrated source

Fresh origin/main was `c0c6ff3be9194495e45abe921181b403da0c3542`. Dedicated worktree: `/Users/tinyserve/Projects/KeineMagie-combined-release`, branch `release/combined-dictation-20261119`.

- Native camera/back navigation, global minimal player and durable Stop: `6cbfb1cf891d8302178e19cfaa918cb737299bdd` (all six candidate commits retained).
- Web spacious cards, word count/decoded duration and authoritative four-stage lifecycle: `dfb3dc729d5f29a6afcb711ae0e6dd2aba9b8578` (both candidate commits retained).
- Native feature-specific translation transport deadlines, eight-second authentication deadlines: `f8834451407b1c5cbbbbe8c900aa8407bd0ec9cf`, cherry-picked as `80d8f59011720a5b5045902715fb1024ea577675` after merge `25790cc`.

The only merge conflict was the comment preceding the identical canceled-before-admission context guard. One guard and the complete Stop ledger remain. Both native catalogs remain byte-identical to the native candidate; no key/locale was regenerated or dropped.

## Independent review correction

Initial combined review found that a committed start/progress whose acknowledgment is lost could leave a durable Stop retrying an obsolete fence forever. Real Go and Swift-controller/Go cold-journal regressions failed before correction.

The server now persists `stop_base`, the revision before the active admission's current ownership began. A named Stop may bridge lost acknowledgments only for that exact admission/client within its uninterrupted ownership interval. Every resume establishes a new boundary, so a foreign takeover—even followed by return to the former client—does not permit an old Stop. Legacy reservations without the field retain strict revision checks. The native controller retains the last acknowledged owned admission identity after interruption. No quota refund, final-reading restoration, authentication weakening or refresh-based fence adoption occurs.

The real bridge checks lost start and progress responses, offline Stop, cold journal restore, successful Check/mode cancellation path, unchanged spent start, then explicit zero-based new playback. Go tests additionally cover handler recreation, idempotent recovery and foreign ownership rejection. A second independent read-only review passed this four-file fix. Suggested extra legacy/lost-resume boundary tests remain nonblocking, not claimed as executed.

**Recovery compatibility:** pre-Stop binaries discard durable Stop fields; even the prior native candidate lacks `stop_base`. The eventual deployment must pin the exact new writer as the recovery target. Never automatically roll back to an older typed writer or restore historical user data/budget holds.

## Executed local verification

Evidence root: `/Users/tinyserve/.hermes/cache/scratch/combined-release-20261119/`.

| Gate | Result and scope |
|---|---|
| Full `go test -race ./... -count=1` after correction | PASS, 90.288s (`go-race-fix.log`) |
| Full Go vet after correction | PASS (`go-vet-fix.log`) |
| Native CI discovery after correction | 64 reported, 1 built-plist skip; 119 actual AppModel lifecycle tests passed (`native-ci-fix.log`) |
| Swift Core after correction | 100 XCTest reported, 4 opt-in fixture skips, no failures; 84 Swift Testing passed, including real delayed-HTTP deadline regression (`core-fix.log`) |
| Actual Swift controller → Go bridge after correction | 3 passed, no skips (`native-go-bridge-fix.log`); includes cold lost-ack recovery and Stop/four-start contract |
| Node, initial integration; web source unchanged by correction | 166 passed, 1 opt-in wire skip (`node.log`) |
| Profile real Go wire/browser | PASS (`profile-bridge.log`); executes the opt-in wire independently |
| Real Apple Vision harness | Six groups passed (`vision.log`); generated printed image, not physical camera or handwriting |
| Initial integration Chromium/Go lifecycle | 30 locale/theme/width cases, zero library media/mutation calls; actual 390px RU dark screenshot inspected (`web-lifecycle.log`) |
| Initial integration real-media policy Chromium/Go | PASS (`web-policy.log`); synthetic audio, not paid provider speech |

Initial-source browser evidence is not relabeled as post-correction evidence. Source and all test fixtures remain synthetic; no real account/provider credentials or paid calls were used.

## Pending mandatory delivery gates

The tool runtime placed the attempted coherent normal-device Release UI execution into **approval-pending**, with an explicit instruction not to reissue/reformulate until decided. This is tool execution approval, not missing release authorization or another visual design gate. No simulator execution was performed in this release task. Existing permitted UUIDs remain `93E1113F-6736-4CCB-827D-0E2F1C3876EA` and `56A70197-59DE-4410-9E76-25272244E9C8`; never create/clone/delete replacements.

Coherent Release UI on both devices, final-source browser repetition, normal main push, CI image publication, locked pinned-image deployment, live HTTPS asset/card verification, one explicit TestFlight dispatch and Apple `UPLOAD SUCCEEDED` readback remain unperformed. No new uploaded build is claimed.

Production readback during this task: remote main still `c0c6ff3`; live OCI revision `78e2ebf589cbee9f574b497892319afa255de121`, image `sha256:c7ee5112434d3d133d3803d9a0f7e6ca7eb212062a2c467ff96dcc0f8a57f1cc`, certificate-validated IPv4 health 200. No production writes.

Original KeineMagie 304 protected dirty-file hashes and exact expanded status, plus AnyProgress (`Projects/anyring`) 13 files/status, verified unchanged. Prior synthetic fixture was preserved under `scratch/dictation-camera-player/fixture-pre-combined-*`; no source worktree was reset. Obsidian overview now distinguishes this unpublished integration from the last delivered build.

The timeout repair does not resurrect the old uncertain translation. Keep it intact; Check result is GET-only. A genuinely new paid attempt requires the user's explicit informed decision. Physical camera/permissions/handwriting, spoken VoiceOver, Apple processing/tester availability remain unverified.
