# Podcast passage stars and non-destructive groups

Local candidate based on `origin/main` at `5d532e9` (includes `f787b40`). No deployment, push, AI generation, or TTS work is part of this change. The original dirty worktree is not modified.

## Contract

A passage remains one original recognizer segment. Its ID is the original zero-based array index within one owner-owned preparation job. The DE/RU pair is one row and one star. Neither transcript arrays nor source text, translations, timestamps, search indices, existing citations, or citation URLs are rewritten.

A group is a maximal run of one or more **starred original sequence indices** in the same owner/job. Neither timestamps nor currently visible/search-matched rows define adjacency. Saving the gap between two runs merges them; removing an interior star splits a run; removing an endpoint shrinks it. The library's existing `favorite_passages` remains the count of original marked segments, not groups. Group count is available as `groups.count`; no new dashboard counter is introduced.

### Persistence and identity

Storage remains the existing owner-hashed `learning/*.json`, with its existing cross-process lock and atomic temp-write/fsync/rename/directory-fsync implementation. The existing `passages` entries retain their exact `{job_id, segment_id, quote}` schema. Additive fields are:

- `passage_group_version: 1`
- `passage_revision`: owner-wide monotonic revision for changed passage membership/group metadata
- `passage_groups`: ordered relationships containing `id`, `job_id`, `segment_ids`, `start`, `end`

Group IDs are `pg_` plus SHA-256 of JSON encoding of the Go struct `{Owner, Job, Members}` (uppercase struct field keys, in that declaration order). Members are ordered original indices. This is deliberately an **exact-membership snapshot identity**, not a persistent annotation container. Identical owner/job/members restore the same ID; merge, shrink, or split creates the corresponding new identities. There is no random merge survivor and no annotation transfer heuristic. Original per-segment marks remain the source of truth. There are currently no group annotations; future group annotations must use an explicit migration/reference policy, not assume IDs survive membership changes.

Each group's `start` is its first member's original start; `end` is its last member's original end. Even irregular timestamps do not reorder membership. Existing navigation continues to use original indices.

The first group read or passage write upgrades a legacy ledger. Migration derives relationships only from valid saved marks whose original quote still matches that index. It never turns vocabulary favorites into passage marks. Unknown future group versions fail closed. Repeated GETs and same-value PUTs retain the same revision and IDs, including the empty-ledger case. Nil/empty JSON collections are normalized for comparison. Other learning datasets survive migration unchanged.

Passage writes and relationship reconciliation share one learning transaction. Lock order is podcast source store, then owner learning store; write authorization is rechecked after queued lock acquisition. A deleted source cannot be resurrected by an in-flight star. Podcast deletion durably removes the source, then removes its ledger marks and group references while retaining the source lock. A failure does not acknowledge success. These are two existing JSON files, **not a cross-file atomic transaction**: if the process dies between writes, the next group GET (including GET for the now-missing last job) repairs orphans before returning 404. A crash can therefore leave inaccessible on-disk references until reconciliation; no invented SQL/FK guarantee is claimed.

### API and compatibility

- Existing `PUT /v1/learning/episodes/{job}/passages/{originalIndex}` with `{ "favorite": true|false }` stays supported for web and native. Existing response keys remain. Additive `passage_groups` contains the complete acknowledged job snapshot.
- New `GET /v1/learning/episodes/{job}/passage-groups` returns `{version, revision, job_id, groups, favorite_segment_ids}`. Arrays are non-null. GET can persist deterministic migration/reconciliation, but never starts a provider request.
- Optional `X-Passage-Owner` must match the authenticated owner if supplied. Native supplies it; legacy web requests without it remain valid. Existing browser cookie/Origin/CSRF checks remain on both routes. Native bearer authentication, foreign-job 404, and revoked-session rejection remain enforced.
- Library/job coverage adds `passage_revision`. Native prefers a newer acknowledged group snapshot's segment count over older library coverage, but a later library revision wins. Old coverage without a revision remains decodable.
- Persistence errors return an error, never a fabricated successful star. Same-value retries do not append duplicate marks or bump revision. Conflicting true/false writes retain existing last-serialized-writer semantics; this is not a new operation-ID replay journal for arbitrarily reordered contradictory requests.

## Native behavior

`EpisodeReaderView` in the fresh base already uses a real windowed SwiftUI `List`, not a `ScrollView`/`LazyVStack`. Trailing native swipe actions now expose Save/Unsave with star symbols; full-swipe execution is disabled. Context menu and named accessibility action provide non-swipe alternatives. Controls retain a minimum 44-point height. Only a small secondary filled-star indicator is added to the timestamp row. No custom pan recognizer, leading swipe, haptic, playback, navigation, search, jump, timeline, or citation behavior is added or replaced.

The server supplies groups once; `PassageGroups` builds its star membership set once on decode. Row rendering does O(1) membership lookup. Original windowing (around the selected index) is preserved for 2,113+ segments.

AppModel owns per-job read/write requests. Writes coalesce while pending, invalidate older reads, apply only acknowledged snapshots, and remain busy through the cache write. Revisions prevent stale response replacement. Failure retains confirmed state and exposes a retryable error; no implicit retry creates work. Existing owner-generation, 401 revocation, reset, and revocable cache lease fences are reused. Groups are optional in `EpisodeLearning` and persist inside the existing `learning` cache dataset, so existing logout purge covers them; no new private cache directory is introduced. Known-owner offline cache remains readable, but writes are disabled. Unknown/different owners do not inherit cached stars.

## Coach and web

Coach enumerates each grouped span once, joins the original member text in original order, and does not offer its individual members as duplicate candidates. Existing source size/admission limits stay in place: a group over the 1,800-rune bound is omitted rather than silently split. This does not prohibit deliberate future exercises from the same source; existing Coach request receipts and repetition behavior are unchanged.

New Coach source IDs encode exact group provenance as `passage-group:{job}:{firstOriginalIndex}:{groupID}`. Assessment resolves the same current group and rejects changed/missing membership; it does not reinterpret an old exercise against a different span. Existing `passage:{job}:{index}` sources remain supported for old exercises. Native and web source links understand both formats and still jump to the original anchor. After group membership changes, the immutable original anchor remains navigable even though that old group snapshot is no longer an eligible current assessment source.

Existing web star PUTs automatically update the same persisted groups. There is no new web swipe UI. Saving or reading stars does not create Coach exercises or start any AI/TTS request.

## Verified locally

- Go red/green for missing group GET, absent deletion cleanup, separate Coach member candidates, empty-read revision drift, expected-owner rejection, queued revocation, and interrupted last-job deletion recovery.
- Go tests cover singleton, nonadjacent runs, bridge, middle split, endpoint removal, duplicate replay, concurrent/order-varied stars, restart, legacy upgrade, source immutability, source-owner/job identity separation, nonmonotonic timestamps, synthetic 2,113 original indices, source deletion races, revoked sessions, and atomic write failure retaining the exact previous ledger bytes.
- Full backend `go test -p 2 ./...` passed. Targeted group/coverage tests also pass under `-race`; `go vet ./...` passed.
- Core `swift test --jobs 2`: 61 XCTest cases (one existing wire fixture test skipped without its dedicated runner), plus 72 Swift Testing cases, zero failures. New tests cover request method/path/body/owner, invalid IDs, legacy optional cache decoding, group round-trip, original-index link parsing, and revision-aware passage counts. The dedicated `verify_podcast_wire.py` runner then passed all six wire tests, including real Go serialization of groups at indices 2012/2013/2112 against the 2,113-segment fixture.
- Actual AppModel lifecycle harness: 98 tests passed. New cases prove acknowledged-star disk persistence across reconstructed offline models, owner separation, stale read/write fencing, duplicate coalescing, failed-write state retention, and revoked/late-reset behavior.
- Web `node --test web/tests/*.test.mjs`: 113 passed, including group source-link compatibility.
- Swift frontend parse of the changed views and `git diff --check` passed. Parsing is **not** iOS typechecking or runtime verification.

## Independent review follow-up

The independent review of `3562cc9` reproduced and fixed four issues with RED → GREEN regressions:

- A group GET authenticated before waiting for the source/learning locks could return private groups and persist migration after revocation. GET now rechecks the request session and cancellation inside both locks before reconciliation; denied reads leave the exact ledger bytes unchanged.
- Coach generation fetched the transcript and relationships separately. Concurrent recognition append plus a new star reproduced an index-out-of-range panic. Generation and group assessment now capture the transcript in the same transaction as the relationships. The concurrent append regression passed three consecutive runs and the race-enabled suite.
- An already-canceled native star task still reached transport and changed server state while discarding its acknowledgement. It is now rejected before transport.
- A superseded native group GET discarded HTTP 401 along with stale content, leaving the current owner writable and cached private content visible. Same-generation 401 now revokes identity even when the content request was canceled/superseded; different generations remain fenced.

Additional review coverage checks the exact 1,800/1,801 **rune** boundary: oversized groups are omitted, never truncated or replaced by duplicate individual-member candidates. Existing grouping, deletion/recovery, auth/CSRF, idempotency and source immutability regressions remain green. No provider requests were made.

Verification after the review fixes: full `go test -p 2 ./...`; `go test -race -p 2 -run 'TestPassage|Test.*Coverage|TestCoach' ./...`; `go vet ./...`; 61 Core XCTest cases (one dedicated-runner skip), 72 Swift Testing cases; all six actual-Go wire tests; **100** real-AppModel lifecycle tests; 113 Node unit tests. The lifecycle harness retains an unrelated pre-existing unnecessary-`await` warning. These are macOS unit/harness checks, not iOS target typechecking.

Integration cautions: the concurrently dirty `candidate/coach-daily-chat` worktree was inspected read-only. It changes `server/coach.go` daily admission/receipt handling, native `AppModel.swift`/Core `Coach.swift`, localization, lifecycle fixtures, and `web/coach.mjs`. Preserve both its admission fences and this branch's atomic group-source resolution/legacy links rather than taking an entire side of any conflict. No combined-branch integration test was run. Row membership remains O(1), and this feature adds no pagination fetch loop. Backend reconciliation still scans all the owner's marked jobs per transaction; Coach can repeat that scan when many jobs yield only oversized/ineligible groups. This is a remaining scaling concern, not a claim of owner-wide constant-time reads.

## Standalone native Release acceptance — November 17, 2026

**Ready for parent integration, not deployment.** Acceptance implementation commit: `6103675b0e73063178bc5cc54727642b0777d997`, on reviewed `da6d678578d0d281e222b128aef77d6a28582780`. This does not contain the separate Coach/Translator integration `6d2b5631d6fe4fd38c3ee6ad4dc515ad09b7a45f`. No merge, remote write, backend deployment, real-user request, paid AI, or provider invocation was performed.

### Actual runtime and transport

- Xcode **27.2 (27B52)**, Release, Swift 6, ad-hoc simulator signing; successful actual iOS target build/typecheck, not only frontend parsing. Used `-jobs 2 -parallel-testing-enabled NO` and one exact destination. No test clones.
- One task-owned **iPhone SE (3rd generation), iOS 27.2**, 375×667 points, UDID `5002FCC4-6475-4111-90F5-02BDE6A0931E`. Light baseline, dark main suite, five locales at ordinary Dynamic Type **XXXL** (`UICTContentSizeCategoryXXXL`, not Accessibility XXXL).
- `native/ci/passage_ui_fixture_test.go` runs through a Go overlay against the real production `newHandler`, auth store, podcast store, learning transactions and API serialization. All files are generated under `t.TempDir`; the fixed loopback listener is `127.0.0.1:18879`. Only GET and passage PUT can reach the handler; unrelated mutations/provider operations are rejected. Synthetic auth tokens stay inside the fixture. Requests record method/path/body/expected-owner/status and passage response bodies, not Authorization headers.
- The opt-in simulator `passage-http` mode forwards the real APIClient requests through URLSession to that loopback handler. The source fixture contains **2,113** original DE/RU segments and a real subscription/preparation relationship. Summary/vocabulary remain the existing synthetic in-memory fixture; no analysis generation is claimed.
- Server-side GET after each gesture verifies the durable group snapshot independently of the UI. Source JSON and its SHA-256 remain identical. Teardown reconstructs the production handler/store and compares complete group snapshots byte-for-byte: **one Go integration fixture test passed**, retaining three groups. See `evidence/passage-groups/production-go-fixture.log`.

### Passing acceptance cases

Four distinct native XCTest cases have passing results on the final production source. No zero-test result is counted:

1. **Native swipe / exact HTTP:** real trailing List swipe, visible Save, 50-point native button, exactly one PUT with `{"favorite":true}`, acknowledged original index 2012.
2. **Bridge, split, navigation and owner cache:** save 2012 and 2014 as separate groups; search `needle` visits those nonadjacent original indices without grouping across 2013; save 2013 bridges; unsave 2013 splits; save/remove endpoint 2015 extends/shrinks; save last original index 2112. Exactly **seven PUTs and four app passage-group GETs**, with matching nonempty authenticated expected-owner headers and complete acknowledged response bodies. Original timeline jump, citation at 2012, Back to source, vertical List scrolling, two repeated library/reader returns, online terminate/relaunch, known-owner offline terminate/relaunch, and replacement-owner empty library pass. Library renders **Ready**, **Translated passages 2,113 / 2,113**, and **Starred passages: 3**. Offline retains stars but offers no swipe mutation; replacement owner cannot see the original episode.
3. **Failed write / revocation:** injected HTTP 503 retains the confirmed star and visibly presents Retry at index 2012. Retry is a read, not a second write. A later actual loopback HTTP 401 purges the open reader immediately and leaves no private podcast tabs/content after offline cold relaunch. Three exact PUT attempts cover success, 503 and 401.
4. **Five locale/context alternatives:** German, English, Russian, Spanish and French XXXL dark small-device runs each perform swipe Save and long-press context-menu Unsave, checking the correct short localized labels and real HTTP state. Menu hit targets measure **250×57 points** in every locale; swipe targets are at least 44 points. Screenshots and AX trees are exported and inspected.

### Runtime defects found and fixed with failing UI regressions

- **Offscreen mutation failure:** error/Retry was the first row of the bounded List, approximately 30 rows above selected index 2012. The failed-write test reproduced an invisible Retry while the star remained. Moved only that error row outside the scrolling List; the subsequent actual screenshot and test show it visible beside the selected passage.
- **Misleading offline action:** native swipeActions exposed an enabled-looking Unsave despite `.disabled(!canSavePassage)`; the offline test failed its disabled assertion. Unavailable/pending swipe actions are now omitted, while model mutation guards and context/accessibility alternatives remain. The offline test verifies no offered swipe action and unchanged stars.
- **Retained private destination after 401:** AppModel and disk were cleared, but the outer NavigationStack retained its pushed closure's original job value. The actual reader still displayed text after HTTP 401. Moved the generation `.id` boundary from only MainTabsView to the owning NavigationStack. The same real-HTTP regression now reaches the login gate immediately and remains private-data-free on offline cold launch. **Preserve this RootView change during integration.**

### Exact run history and limits

`evidence/passage-groups/test-results.json` contains xcresult-derived counts and times. All result bundles are under `/Users/tinyserve/.hermes/cache/scratch/`:

| Bundle | Passed / executed | Interpretation |
|---|---:|---|
| `passage-ui-red.xcresult` | 0 / 1 | Setup failure: fixture source update used an expired worker claim; server never listened. Not a product RED or acceptance. |
| `passage-ui-red2.xcresult` | 0 / 1 | Expected missing simulator HTTP forwarding; synthetic episode absent. |
| `passage-ui-green1.xcresult` | 1 / 1 | First actual native swipe/HTTP GREEN, light mode. |
| `passage-ui-full1.xcresult` | 1 / 4 | Reproduced invisible Retry/offline action; also corrected a test that confused login subject `learner` with opaque authenticated UserID. |
| `passage-ui-full2.xcresult` | 3 / 4 | Grouping/cache/locales pass; real retained-destination 401 defect reproduced. |
| `passage-ui-final.xcresult` | 3 / 4 | Final production fixes pass; coverage assertion alone expected `2113` instead of rendered locale-correct `2,113`. |
| `passage-ui-bridge-green.xcresult` | 1 / 1 | Corrected display-string expectation and explicitly asserted four GETs; complete bridge/navigation/cache case passes. |

The last two bundles jointly establish **4/4 distinct cases passing**, not a falsely reported single all-green full-suite run. Only the test's expected localized number and read-count assertion changed between them. No tests skipped in these native runs. The initial unmodified Release app build had no diagnostics; building the existing entire UITest target emits pre-existing actor-isolation warnings in unrelated test files. The Go overlay file intentionally does not typecheck by itself; it compiles and executes as part of the real server test package.

Previous reviewed unit totals above remain prior evidence: 61 Core XCTest (one dedicated-fixture skip), 72 Swift Testing, six real-Go wire tests, 100 AppModel lifecycle tests, 113 Node tests and full/targeted Go race/vet. They were **not rerun as broad parallel suites during this UI slot**; no backend/Core/model algorithm changes were made here.

### Durable visual evidence

`docs/evidence/passage-groups/` commits **26 original runtime PNGs**, **25 AX text captures**, HTTP snapshots, fixture teardown result, run counts and a SHA-256 attachment manifest. Images are native XCTest/simulator captures, not composed mockups. Key captures:

- `light-passage-swipe-2012-Save.png`, `passage-swipe-2012-Save.png`
- `passage-nonadjacent-search.png`, `passage-original-citation.png`, `passage-last-original-index.png`
- `passage-library-three-stars-not-groups.png`, `passage-cold-online.png`, `passage-cold-offline-owner-cache.png`
- `passage-failed-write-retains-star.png`, `passage-401-purged.png`, `passage-revoked-offline-no-private-data.png`, `passage-different-owner-empty.png`
- `passage-XXXL-{de,en,ru,es,fr}.png`, `passage-context-XXXL-{de,en,ru,es,fr}.png`, localized swipe captures.

Inspection found readable short swipe/context actions and quiet secondary stars in the tested scope. Existing horizontally scrolling section labels are partially outside the narrow viewport; the French search placeholder truncates at XXXL. Context-menu dismissal can reposition the bounded viewport to nearby rows; no transcript identity/text or star target changes. This work does not redesign that existing reader layout. Actual VoiceOver spoken traversal/custom-action invocation, physical devices, Accessibility XXXL, edge-back gesture, sustained performance benchmarking and live authenticated services were not exercised. Context-menu non-swipe operation and exported AX labels/target sizes were exercised. Busy/coalescing/cancellation semantics retain prior AppModel harness coverage, not a new delayed-gesture stress test.

### Reproduce without production data

Generate `native/KeineMagie.xcodeproj` with `xcodegen generate`. Create a Go overlay mapping an otherwise nonexistent `server/native_passage_ui_fixture_test.go` to `native/ci/passage_ui_fixture_test.go`, then from `server` run:

```sh
KM_PASSAGE_UI_FIXTURE=1 go test -p 1 -overlay /absolute/overlay.json \
  -run '^TestNativePassageUIFixture$' -count=1 -timeout=95m -v .
```

Wait for `PASSAGE_FIXTURE_READY` and successful `GET /_fixture/state`. On the assigned simulator only, run from `native`:

```sh
xcodebuild -quiet -project KeineMagie.xcodeproj -scheme KeineMagie \
  -destination 'platform=iOS Simulator,id=ASSIGNED_UDID' -configuration Release \
  -derivedDataPath /absolute/scratch-derived-data -resultBundlePath /absolute/result.xcresult \
  -jobs 2 -parallel-testing-enabled NO \
  -only-testing:KeineMagieUITests/PassageGroupsUITests \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test
```

Finish with `GET /_fixture/stop` so the Go test performs the independent durable reconstruction check; parse xcresult test counts and inspect exported attachments. The control paths are synthetic-loopback test infrastructure, never production endpoints. Reuse one simulator; do not run against any user's production cache/credentials.

### Handoff and resource release

Only owned simulator `5002FCC4-6475-4111-90F5-02BDE6A0931E` was shut down; the loopback Go server was stopped and passed. Final inspection showed no xcodebuild, swift-frontend or server.test process running, **45% memory free and 13 GiB disk available**; nine pre-existing booted devices were left untouched. The UI slot is free for AnyProgress. No other repository or original dirty entry was modified.

Parent must review these three small runtime fixes and merge shared-file changes onto the separately prepared Coach/Translator candidate, then perform its one combined Release UI run. Keep atomic group-source resolution, prior auth/cancellation fences, this owning-stack identity reset, and both sibling features rather than taking an entire conflict side. No combined-branch integration test or deployment is claimed here.
