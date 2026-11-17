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

## Explicit remaining release gates

No Xcode build or simulator session was started: Coach and Translator workstreams are sharing the host and the parent requested one sequential slot. This is a unit-tested local candidate, **not simulator-approved or release-ready**.

During that slot, build/typecheck the iOS target, then exercise actual trailing swipe → Save → exact PUT → group GET → terminate/relaunch → persisted stars on the 2,113-row fixture. Verify adjacent/nonadjacent search matches, bridge and split, scroll/timeline/time jump, citations and return, back swipe, vertical scrolling, busy/error/revoked/offline-owner states, context menu, VoiceOver custom action, 44-point targets, Dynamic Type, and quiet icon rendering. Export and inspect real Release screenshots; no screenshots of this candidate currently exist. The supplied `img_89497f25a98b.jpg` was inspected as layout context only, not presented as candidate evidence.

Parent integration/review should inspect shared-file conflicts in AppModel, Podcasts/EpisodeLearning/Coach core types, localization, Coach server source resolution, and the lifecycle runner. The original dirty main tree and concurrent sibling branches must remain untouched. No push/deploy is authorized here.
