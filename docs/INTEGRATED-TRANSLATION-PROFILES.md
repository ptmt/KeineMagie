# Translation profiles + Coach / Daily / Dictation / passage integration

## Scope — November 17, 2026

Local branch `integration/translation-profiles-coach-local` in
`/Users/tinyserve/Projects/KeineMagie-profile-integration` starts at exact combined
base `277d7c3ea993d458b57fb11199a627680ff775e9`. It integrates independently reviewed
profile source `a82728d0cc7dd3af96b4a00795ed6680edb7a860` from
`/Users/tinyserve/Projects/KeineMagie-profile-review` (`review/translation-profile-sync`).
The original uncommitted implementation worktree remains untouched.

This is a local integration, not a published release. No push, deployment, upload,
production account/profile inspection, or paid AI/TTS call was performed. Later
Dictation review/playback/heading/ellipsis work is deliberately **not included**;
parent coordination must combine that work and verify native parity before publication.

## Review and integration corrections

The independent source review reproduced and corrected four defects, each with a
failing regression first: lost-ack replay rebasing a queued edit over another device;
Go's lossy replacement of malformed Unicode JSON; a superseded native 401 retaining
its forgotten on-disk journal; and duplicate identical browser legacy imports changing
the same receipt's method/body. See `TRANSLATION-PROFILE-SYNC.md` for protocol details.
A real-handler write held after initial authorization also proves token revocation
prevents the resumed write from creating a profile file.

Combined-tree testing found and corrected two further production seams:

- A cached older `index.html` lacks the new synchronization controls. Unconditional
  accesses crashed the current application module before the episode shell mounted.
  New control accesses are optional; the existing mixed-version browser regression
  now passes for all four stale resources and optional reader-import failure.
- A native editor opened with separately updated record and revision State could
  capture revision zero. The actual Release offline edit produced a persistent PATCH
  with base_revision zero and a false conflict. Capture record + revision together
  in one Identifiable sheet value; the real journal/wire now acknowledges the edit.

The separate Daily harness needed the additive AppModel extension copied into its
portable target. Its actual compile failure was retained, the harness was repaired,
and all 16 Daily/Coach tests passed. No production behavior was weakened for a guard.

Only the localization catalog required Git conflict resolution. A duplicate-key-aware
recursive three-way JSON merge used actual objects `e8ed89e`, `277d7c3`, and `a82728d`.
It has **417 keys**: all **409 target keys** unchanged, plus eight profile keys with
all five locales. The verified semantic merge was inserted without reformatting the
existing catalog (280 added lines, zero removed). AppModel and API DTO changes are
additive; existing owner generation, cache/outbox, passage and Daily lifecycle fences
remain in place. Focused Dictation playback work was not imported.

## Fresh combined-tree non-UI gates

All data is synthetic and isolated; logs are under
`/Users/tinyserve/.hermes/cache/scratch/profile-review/`.

| Gate | Actual result |
| --- | --- |
| Full Go `-race -count=1 -timeout=300s -json ./...` | 554 passing / 14 skipped test records, zero failures |
| `go vet ./...` | Pass |
| Node web + Dictation onboarding | 144 pass, one dedicated profile-bridge skip |
| Dedicated profile Node → real Go wire | 8 pass, zero skips |
| Swift Testing Core | 79 pass |
| Actual AppModel against profile Go bridge | 113 pass, including two independent models |
| Actual Coach two-client race-enabled Go bridge | 113-test AppModel suite and Go bridge passed |
| Daily entry / foreground-only haptic harness | 16 pass; no physical-haptics claim |
| Actual Go podcast JSON → Swift | 6 pass |
| Python native CI with this built Release Info.plist | 55 pass, zero skips; embedded AppModel 113 pass |
| Profile Chromium acceptance | 13 checks, two real contexts, desktop/mobile, zero inference requests |
| Real episode tabs | 10 locale/width cases, keyboard/search/history/AX, 2,113 segments, zero AI POSTs |
| Mixed-version / lifecycle / owner Chromium suites | All passed after the cached-HTML correction |
| Translation followup Chromium | 37 checks passed |

Skipped opt-in wire gates in generic invocations are not presented as generic passes;
the dedicated actual-wire invocations above execute their relevant paths separately.

## Native Release gate

Parent assigned the heavy simulator slot after the AnyProgress worker completed.
One new isolated iPhone SE (3rd generation) is used:
`56A70197-59DE-4410-9E76-25272244E9C8`, iOS 27.2, dark appearance.
Only that device is controlled. Xcode uses two jobs and disables parallel testing;
there are no simulator clones. Synthetic loopback Go fixtures own ports 18879/18880.

The new profile UI suite exercises real legacy migration, captured editing revision,
foreground incoming polling with keyboard/draft retention, explicit keep-both,
offline cold relaunch and eventual write acknowledgement, remote selected-profile
deletion, owner revocation and offline purge, plus five-locale large-text editor captures.
The final combined invocation also selects every previously accepted Coach/Daily,
Dictation, Translator and passage test from the 21-test base gate.

**Current native gate status: running; completion is not claimed here yet.**

Initial failed bundles are retained, not relabeled successes. An early probe mixed an
OS background transition into the focused-edit test and lost the nested editor; the
foreground polling test isolates the synchronization requirement. A speculative move
of the nested sheet did not fix that probe and was fully reverted. A later real UI
failure exposed the stale revision described above. An eight-second recovery wait was
shorter than the documented 30-second poll after foreground revalidation; the final
wait covers that interval while still requiring the actual server title to change.
Native Normal is represented by no selected style, not a nonexistent Normal button;
the deletion assertion checks the actual strip's selection state.

## Isolation and release boundary

Before/after snapshots verify the original checkout's **59 status entries / 304 file
hashes** and expanded porcelain exactly unchanged. All 30 dirty implementation paths
and the clean combined base worktree are unchanged. The separately delegated focused
Dictation worktree changed during its own parallel work; it was never edited here.
All other pre-existing KeineMagie worktree manifests match. AnyProgress was not edited.

Parent review, coherent integration of the newer Dictation work, and its native parity
remain mandatory. Earlier user publication authorization does not authorize pushing
this older partial candidate by itself.
