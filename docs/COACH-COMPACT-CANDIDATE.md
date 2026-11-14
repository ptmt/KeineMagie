# Coach compact review and release

## Independent review closure

- Fetched `origin/main`: still exact base below. Reviewed actual source diff and existing owner/citation/answer-privacy tests. No release-blocking code defect found. Outbox, flame assets, catalog advisory, header and web geometry files are unchanged; dirty original main and parallel Diktat worktrees are not release inputs.
- Closed the new logging coverage gap with an isolated subprocess exercising real handlers against **synthetic** provider transports: malformed request, missing provider connection, catalog failure, inference transport failure and invalid model result. Exactly five random-reference request logs and two fixed-code failure logs; malicious request headers, synthetic learner/source/owner/token/error sentinels never enter stdout/stderr. Full Go race suite **73.405s**, vet passed after adding this test. Initial new DELETE assertion incorrectly expected 400; corrected to actual HTTP 405 (test-only).
- Independently reran **81 Node**, **50 native CI (1 skipped)** including **42 AppModel** lifecycle tests, and **17 XCTest + 68 Swift Testing** Core tests. All passed. Source scan found no added hardcoded secret, shell/eval/pickle hazard; `git diff --check` passed.
- Extended actual Chromium fixture flow to open Profile and submit both correction and exclusion, retaining original `beim` and original ambiguous outcome. Full shell correct/wrong/ambiguous/skip/reload/cancel, citation navigation, five locales, reduced-motion CSS, 390px composer and logout passed. No real inference.
- Actual signed Release simulator: **6 Coach UI tests passed**, no failures/skips/runtime warnings. Added Profile correction/exclusion menu reachability. Set isolated simulator appearance using `simctl ui … appearance dark`, read it back as `dark`; screenshot inspection confirms actual dark rendering. Five locale feedback, maximum Dynamic Type/Profile, source and real keyboard composer/send checks passed. Native ReduceMotion setting enabled for run; this alone is not an animation timing assertion. Web reduced-motion assertion is actual computed CSS.
- Independent result `/Users/tinyserve/.hermes/cache/scratch/coach-independent-ui.xcresult`; attachments `/Users/tinyserve/.hermes/cache/scratch/coach-independent-shots/manifest.json`. Inspected actual dark large-text `82BA8F9B-787B-41E5-8BE7-4B79CBD0F74B.png`, keyboard `4B7367B0-A169-4BF0-B89D-FE4B7525A1A7.png`, Profile menu `1924522F-350C-456C-AFA4-A21E8D86E1A1.png`. Native keyboard layout has no clipping; large-text content is scrollable, screenshot alone does not prove every offscreen element. Existing compile actor-isolation/debugger lookup warnings remain; xcresult is Passed and signature verified.
- Historic reported connection failure remains **UNKNOWN**. This is clearer boundary reporting and privacy-safe diagnostics, not a proven OpenAI outage fix. Headers apply inside authenticated Coach handler; outer authentication/CSRF rejection may precede them. Upstream HTTP-vs-stream attribution and a client support-details sheet remain follow-ups.

## Release status

- Source **`03599b00b2967132e43ee7f0221acd443a9609b8`** committed from this scoped worktree, normal non-force push/readback on main. Backend deployed **before** explicit `publish=UPLOAD` dispatch.
- Server CI [43580770576](https://github.com/ptmt/KeineMagie/actions/runs/43580770576), build job `132404836479`, exact source **success**. Push-only iOS validation [43580770543](https://github.com/ptmt/KeineMagie/actions/runs/43580770543) success; upload correctly skipped.
- Clean committed archive, network-disabled local arm64 Docker build steps. Live backend **`sha256:6b79445bde222c063bc61de23d4f434ad737d6e723ae3fe62fdd8db7299bb9fe`**, exact OCI revision; container `9acfd5adca2329b113aff5b37a2f3b7c1cf4b36480eb51c62acc71f0cd02c286`. Binary SHA256 **`297ca8f31a19fe4d3bf9d2d488732c267325a4a76687aa2c4f9253a2c1daf5b6`**. This includes actual Go diagnostic changes, not an assets-only release. Existing documented local Compose workaround, distinct from CI registry artifact.
- Original base + durable override merged configuration changed only backend image. Nonblocking store/account-active locks, idle-state revalidation, backend-only stop and released lifetime runner lock respected. Worker **`sha256:a61794a3d7e74b63d9626c453f3b0bac1b9f9f1351b0bb6349ccf564bded9382`**, all worker/unrelated container IDs, environment, resources, mounts, routing labels and internal network unchanged.
- **9 nonruntime durable files byte-identical** across replacement; no active jobs, 1 completed job, 1 subscription, 2113 segments/translations. Private backup/readback: `deployment/release-coach-compact-20261114T093018Z/verified.json` under the existing service directory, mode 0700/0600. Rollback uses saved `compose.previous.yml` and prior backend **`sha256:c82d870356cefa242bbfd873bc2b5fb50d44ccaee7592e9b6639f41844423cc4`** with original base and backend-only `up -d --no-deps --pull never keinemagie`; never restore historical data. Prepared, not destructively exercised.
- Public HTTPS health **200**, **21/21 public assets exact** against committed archive; CSP/no-store intact, protected session/Coach/podcast GET **401**, source/secret/data paths **404**. Existing no-Origin legacy translations gate remains **503**, no auth weakening. Real guest Chromium five locales × four widths, no overflow/page errors; signed-in private/live inference not exercised. Evidence: `/Users/tinyserve/.hermes/cache/scratch/km-coach-compact-public-verified.json`.
- Explicit iOS [43580893096](https://github.com/ptmt/KeineMagie/actions/runs/43580893096) exact source **success**; validate job **`132405715622`**, upload job **`132406528728`**. Apple archived build **`2743.33.92`**, `VERIFY SUCCEEDED with no errors` at **09:38:35Z**, **`UPLOAD SUCCEEDED with no errors` at 2026-11-14T09:39:33Z**, delivery `3b5eb6ca-0eb9-4f55-a166-b7283e060075`. Cleanup succeeded. Local watcher timeout was resumed on the same run; no duplicate dispatch.
- Original dirty main **54 file fingerprints unchanged**. Diktat worktree, credentials and domain untouched; no provider inference, paid retry or production learner mutation. Apple processing, tester availability, physical-device behavior and historical error root cause remain unverified.

## Original implementation record

Base: `d99427b8dd9cf19fae2041066410c686e9d7ab0a` (`origin/main`, fetched before work).
Worktree: `/Users/tinyserve/Projects/KeineMagie-coach-compact`, branch `candidate/coach-compact`.
No commit, push, deployment, real inference, paid retry, or credential/data-store inspection.

## Changes

- Web and iOS suppress recognized generic missing-preposition/word instructions only when a cloze blank is present. Useful additional constraints and rephrasing instructions remain. Narrow five-language matching avoids deleting arbitrary model context.
- Remove category/time metadata and review/Skills controls from exercise bubbles. Keep observations and per-attempt correction/exclusion in Profile; underlying evidence/schema/grades are unchanged.
- Preserve literal submitted answers. Unknown outcomes remain abstentions, with plain localized wording (Russian: «Не могу уверенно проверить»), not a false correct/wrong grade.
- Explanation is immediately visible after submission; before submission it remains behind an explicit Hint. Source disclosure is named Source after submission. Valid local links say Saved translation / Saved podcast passage; raw IDs are never rendered as text. The source ID stays in the owner-scoped backend and routing contract.
- Existing keyed bubbles, reduced-motion CSS/native transitions, input drafts, source navigation, and keyboard-safe composer retained.

## Screenshot diagnosis

The supplied image shows italic `beim` from `attempt.answer`, not a model-suggested answer. Actual sentence: `Ich war einmal ___ diesem Kurs dabei.` Correct insertion is `bei`; `beim` means `bei dem` and duplicates the determiner before `diesem`. Current backend compares normalized exact strings against model-supplied accepted/known-incorrect arrays, abstaining for all other answers. It does not call a model to grade each attempt. We did not inspect the user's private stored arrays, so the exact original list cannot be asserted. A regression reproduces this sentence with `bei` accepted and `beim` unrecognized, preserving both the original answer and ambiguous outcome. No grading heuristic was added.

## Connection error investigation

The original `coach.error.network` did **not** establish an OpenAI disconnection:

- Web used it for unknown HTTP status, malformed JSON response and unknown thrown errors, as well as failed fetch.
- Native used it for all non-CoachServiceError exceptions (including decoding and URL timeout), and unrecognized HTTP errors.
- Provider auth/catalog have distinct server error codes. Generation errors currently return a durable failed/canceled turn, not the network error key. Therefore the reported phrase alone cannot identify OpenAI failure.

Read-only production log query: `docker logs --since 24h --tail 2500 --timestamps tinyserve-keinemagie-1`, parsed in memory and printed only allowlisted route/method/timestamp/duration. No bodies, owner IDs, credentials, or provider errors printed. Existing request logging has **no HTTP status or phase**. Relevant sample: POST at `2026-11-14T07:19:08.010797843Z`, 7.397144483s; POST at `2026-11-14T08:47:09.711630688Z`, 4.035554ms. These timings do not identify the user's failing request or establish provider failure.

Candidate separates client transport, timeout, server HTTP error, response decoding and unknown failures, retaining session/catalog/provider-auth distinctions and no automatic retry. Recovery asks to refresh saved chat before resending, because dispatch/save outcome may be unknown. Safe server diagnostics now add random `X-Coach-Request-ID`, fixed `X-Coach-Phase`, status and duration; generation failure logs distinguish model result validation from generic inference failure. No raw error text/owner/request content is logged. Diagnostics are server headers/logs only; this candidate does not yet expose a client support-details sheet. The shared Responses reader still collapses non-200 upstream status and some stream failures; detailed upstream HTTP/auth-vs-stream attribution remains a follow-up, not a claim of this patch.

## Verification

- Full web Node suite: **81 passed**. Focused Coach suite: **8 passed**.
- Synthetic real Chromium full-shell test passes: correct/wrong/ambiguous/skip/reload/cancel, exact `beim` preserved, assisted hint and retained draft, source deep link/Back, keyed identity, five locales, reduced motion, mobile composer and logout.
- Full Go suite: `ok diktat/server 63.314s`; focused Coach tests pass, including privacy gates and exact-sentence abstention.
- Full Swift package: **17 XCTest + 68 Swift Testing tests passed**; **6** Coach XCTest cases included.
- Native CI discovery: **50 tests, OK, 1 skipped**; compact contracts and seven localization tests pass. Existing lifecycle harness also exercised.
- Actual ad-hoc-signed Release simulator app: **5 Coach UI tests passed**, iPhone 17e / iOS 27.2 / isolated device `3CBBA16A-27B3-4FE4-83B8-69AD6359A162`. Includes five locale launches, visible feedback/explanation, right/wrong/ambiguous/skip/cancel, source navigation, large text and keyboard reachability. Compiled Release localization values checked for eight Coach keys in all five locales; signature verified.
- Two initial new five-locale UI test runs failed because the test assumed an English tab label then a nonstable SF Symbol-derived accessibility ID in Russian. The final test uses the actual localized tab names and all five pass. Existing unrelated XCTest actor-isolation build warnings persist; final result has no runtime warnings.
- No release/user data changes; parallel Diktat and dirty main worktrees untouched.

## Evidence (synthetic transports; real rendered applications)

Web evidence directory: `/Users/tinyserve/.hermes/cache/scratch/coach-browser/`
- `exact-course-mobile.png` — inspected; literal beim, plain uncertainty, explanation, Source, composer all readable.
- `exact-course-desktop.png`, `desktop-feedback.png`, `citation-return.png`, `mobile-reduced-motion.png`.

Final native result: `/Users/tinyserve/.hermes/cache/scratch/coach-compact-acceptance-ui.xcresult`
Attachments: `/Users/tinyserve/.hermes/cache/scratch/coach-compact-acceptance-shots/manifest.json`
- Russian: `896875DD-CD2C-43DF-8293-EBE93973D282.png` (inspected).
- Keyboard: `55E39898-1F6D-4E3C-974A-F7EB7E6D242E.png`.
- Feedback: `DF6EF650-1BEF-416D-89EC-47CFB23E5F85.png`.
Earlier Release keyboard/feedback captures were also visually inspected.

Limitations: no real account inference quality audit, physical device run, production root-cause correlation, or deploy. Synthetic native explanation remains original German by design; UI locale changes do not rewrite learning content. The large-text test's legacy name says dark, but no actual dark appearance was set in this isolated simulator; do not claim dark-mode verification.
