# Translation profile synchronization

## Status and integration boundary

Implementation branch: `translation-profile-sync`, isolated worktree
`/Users/tinyserve/Projects/KeineMagie-translation-profile-sync`.
Base: `e8ed89e` (documentation following translator controls release `b52c48d`).
This is a locally validated integration candidate, **not a deployed release**.
No merge, push, deploy, Xcode app build, or simulator run was performed for this task.
The original checkout's 59 dirty paths were left untouched. The parallel Coach/Dictation
worktree and simulator `sa-0-374f8e76` were not used.

Custom styles and selected templates synchronize. Normal/Friendly/Formal remain built-ins;
selecting them never creates server records. Profile IDs, full titles, full instructions,
creation order, and local selection identity are retained; equal names/instructions do not
identify a profile. Local editor buffers and translator drafts are not synchronization state.

## Wire protocol

`/v1/translation-profiles` supports GET, PUT (create/import), PATCH (edit), DELETE.
Existing native bearer and browser HttpOnly-session authentication apply. The browser route
is included in the existing origin/CSRF checks. Native requests include
`X-Translation-Owner`; a mismatched expected owner is rejected. Server ownership comes from
the authenticated session, never a body field.

GET and successful mutations return:

```json
{"revision":1,"items":[{"id":"custom-example","title":"Work","instruction":"Keep the tone concise.","revision":1,"deleted":false}]}
```

Mutations send `operation_id`, `id`, `base_revision`; PUT/PATCH also send `title` and
`instruction`. DELETE must not carry text. Create uses revision zero; edits/deletes use the
last observed record revision. An editor captures that revision when editing begins, not
when the user eventually presses Save.

- IDs/operation IDs: `^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$`; built-in IDs are reserved.
- Title: non-whitespace, at most **60 Unicode scalars**. Instruction: non-whitespace,
  at most **1,000 Unicode scalars**. Accepted values are not truncated or normalized.
- At most **50 live profiles** per owner. Tombstones do not consume live capacity.
- `409`: stale revision, deleted record, or an operation ID reused with different content.
- `422`: capacity; `400`: validation; `401/403`: auth/owner rejection; persistence failure
  is not acknowledged and returns an error. `404/405` from an older server keeps local data.
- Replaying an identical operation returns the current snapshot without a second mutation.
  Clients require the acknowledged record/revision before removing a pending operation.

The durable owner file is beside configured history storage:
`translation-profiles/<hashed-owner>.json`. It uses the existing private-directory/private-file
atomic writer and file locks, in auth-then-owner lock order. Session revocation is rechecked
under the auth lock before reads/writes. The file includes operation-body digests as receipts;
receipts are not returned to clients. Deleted records retain ID/revision but erase their text.
Receipts and tombstones are retained (not pruned heuristically). The file has a 32 MiB bound;
operators must not drop receipts/tombstones to reclaim space without a future migration policy.
No profile data enters provider configuration or credential stores.

## Migration and offline behavior

Legacy sources:

- Web: `keinemagie:translation-prompts:v1:<encoded-owner>` in that origin's localStorage.
- iOS: `translationShortcuts.v1.<encoded server/owner tuple>` in UserDefaults.

New journals are owner **and origin** scoped and require verified identity. They persist
before any request or optimistic acceptance. A migration marker is committed together with
all its pending imports. Failed local writes cannot be reported as saved or sent. No guest
journal is created. Account changes fence late responses and isolate other owners' journals.

Import identity is SHA-256 over the concatenation of UTF-8 byte-length framed legacy ID,
title, and instruction (`<byte length>:<value>` for each). The first 16 digest bytes form an
uppercase UUID-style ID; the operation ID is `import-<ID>`. Therefore identical records
reimport idempotently, while the same old ID/name with different full contents remains distinct.
The Swift/JavaScript Unicode fixture is asserted in both languages.

Legacy data is not deleted or rewritten during migration, including after successful sync.
Native's old **40 Swift Characters** title decoder remains readable. A rare old grapheme-rich
title longer than the new 60-scalar bound stays visible and queued, with an explicit validation
notice; the user can shorten it without losing the original legacy copy. A corrected server
record/tombstone prevents that rejected old import from overlaying it after relaunch/logout.
The existing instruction limit was already 1,000 scalars and is unchanged.

Each mutation has an immutable retry identity. GET refreshes merge with the local pending
projection, never silently overwrite it. Conflicts offer **use server** or **keep both**;
keep-both creates a new ID. A deleted server record is not resurrected by an old import or
stale edit. Selection follows ID, and deletion of the selected profile falls back to Normal.
At capacity, imports/edits stay queued; an independent deletion may go ahead of a blocked
create to free a slot, but never ahead of earlier operations on the same record.

Explicit logout and 401 purge the active private journal before forgetting its scope.
The historical legacy store remains untouched, matching its pre-existing logout behavior;
it can safely reimport using retained server receipts/tombstones. Ordinary account switching
does not destroy another owner's unsent journal. Older-server errors preserve readable legacy
and queued state rather than resetting or falsely acknowledging it.

The web polls while visible; iOS polls while the translator scene is active, at 30-second
intervals, with coalesced work and scope/generation fencing. Profile editing, CRUD, migration,
and polling call no inference or TTS endpoint. Only explicit translation submission captures
an immutable instruction snapshot through the existing bounded, untrusted input payload.
A later style change cannot mutate an in-flight translation.

## UI and accessibility

Only the redundant visible web source/result headings were hidden with `sr-only`; associated
localized labels remain in the accessibility tree. Native already had no redundant section
headings on this baseline; its source AX title/placeholder is retained and its result group
now explicitly uses the existing localized Translation AX title. History/other section titles,
clear/copy/edit/clarify controls, input footer styles, native pending behavior, and real web tabs
remain intact. Hidden web labels have an explicit trailing-control alignment rule.

Sync/privacy/conflict/capacity/validation copy is provided for de/en/ru/es/fr. Management says
custom styles synchronize with the account and advises against putting secrets in instructions.

## Executed verification

All fixtures use disposable accounts and synthetic profiles, never personal saved prompts.
The acceptance bridge runs the real Go production handler and rejects inference/TTS requests.

| Gate | Result |
| --- | --- |
| `go test -race -json ./...` | 504 pass, 14 skip, 0 fail (518 discovered, including subtests) |
| `go vet ./...` | pass |
| `node --test web/tests/*.test.mjs` | 120 pass, 1 bridge-only skip, 0 fail |
| Node tests against the live Go bridge | 7 pass, 0 skip/fail (includes six nested cases) |
| `swift test` in `native/Core` | 78 pass |
| actual AppModel lifecycle harness with live Go bridge | 107 pass, including two independent AppModels |
| native surface/shortcut static tests | 9 pass |
| Chromium acceptance, two real contexts | 13 checks pass, desktop and mobile |
| `git diff --check` | pass |

Coverage includes same-ID/different-content migration, Unicode, independent edits, explicit
conflicts/keep-both, offline/reload, lost acknowledgement, tombstone reimport, owner/401/stale
responses, server restart, write failure/no acknowledgement, capacity recovery, retained
selection, editor focus/draft preservation, and no inference calls from profile operations.
Native logout regression and browser synchronization waits were fixed and rerun green.

Commands:

```sh
(cd server && go test -race ./... && go vet ./...)
node --test web/tests/*.test.mjs
(cd native/Core && swift test)
python3 -m unittest native.ci.test_tabs_shortcuts native.ci.test_translator_surface
/path/to/playwright-python web/tests/profile_sync_acceptance.py
```

Acceptance requires Python Playwright with Chromium; the script owns a disposable Go server
and runs wire Node tests plus the generated Swift AppModel harness. `KM_PROFILE_BROWSER_ONLY=1`
limits it to browser acceptance. No production credentials are required.

Evidence (local scratch, not shipped):

- `/Users/tinyserve/.hermes/cache/scratch/profile-sync-browser/profiles-desktop.png`
- `/Users/tinyserve/.hermes/cache/scratch/profile-sync-browser/profiles-mobile.png`
- `/Users/tinyserve/.hermes/cache/scratch/profile-acceptance-final.log`
- `/Users/tinyserve/.hermes/cache/scratch/profile-go-race-final.json`
- `/Users/tinyserve/.hermes/cache/scratch/profile-node-final.log`
- `/Users/tinyserve/.hermes/cache/scratch/profile-core-final.log`

The desktop/mobile screenshots were inspected: no redundant headings, trailing controls are
retained, style buttons wrap without horizontal clipping. Native screenshots are **pending**.

## Independent source review — November 17, 2026

Reviewed in isolated `/Users/tinyserve/Projects/KeineMagie-profile-review`, branch
`review/translation-profile-sync`, without modifying the implementation worktree.
The original checkout and every pre-existing sibling's dirty-file status/hashes were
captured before review in scratch `profile-review/before.json` (304 original files).
No private user profiles were read; all fixtures are synthetic.

Four reproduced defects were corrected with failing tests first:

- Lost-ack replay returns the latest server snapshot. Both clients previously rebased
  a dependent queued edit over another device's changed content, silently overwriting
  it. Rebase now requires the acknowledged content to match the submitted content;
  otherwise the stale revision remains and yields an explicit conflict. The actual
  Go wire test includes two clients, a lost acknowledgement and an intervening edit.
- Go JSON decoding silently repairs malformed UTF-8/unpaired surrogate escapes.
  Reject these before decoding, retaining valid surrogate pairs, literal escapes and
  actual replacement characters without normalization.
- A superseded native request's 401 could leave its journal on disk after an earlier
  content reset forgot the active scope. Purge the captured scope before revocation;
  the actual AppModel regression reopens the real private journal to verify removal.
- Identical duplicate legacy browser entries previously queued the same receipt twice,
  causing the second import to change method/body and conflict. Deduplicate only exact
  content-derived import identities; different contents remain distinct.

Added a real-handler revocation test that blocks a write body after initial authorization,
revokes the token, then proves the resumed write returns 401 without creating a profile file.
Reviewed auth→owner lock order, private journal/outbox persistence-before-send, tombstones,
owner replacement, older-server preservation, scalar boundaries, capacity deletion recovery,
editor revision capture, focus/draft preservation and unchanged inference boundaries.

Fresh baseline at detached `e8ed89e`: Go race 497 passing / 13 skipped records; vet pass;
Node 113 pass; Swift Testing Core 72 pass; actual AppModel 101 pass; Python native CI
54 discovered, one existing processed-app skip. No baseline failures.

Reviewed source: Go race **506 pass / 14 skip**, vet pass; Node **122 pass / one bridge
skip**; Swift Testing Core **79 pass**; browser acceptance **13 checks**, live Go Node
wire **8 pass**, actual AppModel **108 pass** with the profile bridge. Full Python CI
previously passed 55 discovered / one processed-app skip; its embedded AppModel suite
was rerun after the final auth fix via the bridge. Native Xcode/Simulator gates remain
unexecuted; no build slot was used. Logs are under scratch `profile-review/`.

## Rollout and remaining gates

Integrate/review before release. Deploy the backend plus new static module before/with web and
before iOS; `server/static.go` and `server/Dockerfile` explicitly include `profile-sync.mjs`.
Back up the profile directory with existing account/history storage. Do not wipe client journals
on downgrade. New clients remain local/offline against an older server; older clients remain
local-only and cannot offer bidirectional synchronization until upgraded.

Parent must assign the iOS UI/build slot before Xcode/simulator validation: app build, localized
VoiceOver output group, editor focus/revision behavior, offline/conflict notices, iPhone sizes,
keyboard/Dynamic Type, and existing translator/footer/pending regressions. Independent integration
review and production rollout are not claimed by these unit/wire/browser results.

Expected shared-file reconciliation with Coach/Dictation work: `native/App/AppModel.swift`,
`native/App/Localizable.xcstrings`, `native/App/TranslatorView.swift` (one AX line),
`native/Core/Sources/KeineMagieCore/APIClient.swift`, `native/ci/test_connection_lifecycle.py`,
`web/app.mjs`, `web/core.mjs`, and possibly server route/static/Dockerfile lists. The substantial
new logic lives in additive profile files to reduce overlapping edits.
