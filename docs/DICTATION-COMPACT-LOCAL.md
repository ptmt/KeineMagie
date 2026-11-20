# Dictation compact detail — local only

Supersedes the prior detail layout in `DICTATION-INTEGRATION-LOCAL.md`. Not pushed, deployed, uploaded, or applied to a production account. Released Coach remains at `5aa7ad93424640092c3f7a7470936fc20dda9ac2`.

## Presentation contract

- One primary transport below the timeline. Preparation, Stop, manual Next and optional final reading retain their actual state-machine semantics. Check stays explicit, below the answer; whole-attempt completion remains an explicit choice.
- Mode, speed, repeat count, longer inter-repeat gaps, extra replay, whole-text completion declaration and audio/assessment information live in the existing ellipsis. Opening the menu performs no command. Pacing changes keep their before-first-listen restrictions. The completion declaration remains explicit and defaults to partial, with the existing Check guards unchanged.
- The instruction card, repeated phase heading, writing paragraph, Up next paragraph and Show timeline control are replaced by an always-visible vertical plan. Sentence headings group actual fragments; they are not extra audio steps. Current-row writing/repetition/gap status is compact. Completion requires actual ended planned receipts, not an admission or a stopped listen.
- New policy-2 plans carry numeric sentence/fragment provenance from the original server-side sentence and clause splitter. The public plan retains numbers while source text stays redacted. No original words appear in timeline labels. Audio assets, starts, final allowance and repeated-asset identities remain unchanged. Existing plans lacking that metadata remain flat; no fabricated hierarchy or implicit migration.
- The root's selected tab plus exact destination attempt controls accessory visibility. The actual native accessory host is disabled on that detail, not merely its contents. Back/list/other tabs restore it. Navigation does not recreate the coordinator, admit audio, pause, stop or discard the draft. Opening another attempt retains the existing explicit replacement behavior.
- Web uses the same hierarchy and secondary-menu placement; no nonexistent web global player was introduced.

## Evidence status

Acceptance is in progress. Earlier 9/9 receipts describe the previous layout, not this revision. Final source-bound counts and preview paths will be recorded after the fresh serial normal/small runs.

Observed RED: the actual Release detail contained the global accessory; actual Release lacked the requested hierarchy and retained the old instruction/settings surface; actual Chromium retained the instruction block; Go plan JSON lacked provenance. A later native probe verified hidden-detail/reappearing Back and cross-tab player behavior, and exposed a test assuming menu Picker values were nested. The menu now uses explicit compact submenus. A short synthetic audio clip was too brief for a playing screenshot; only the explicitly named Timeline fixture uses longer generated PCM. No live provider call was substituted.

Moving Check below the answer exposed keyboard geometry defects. The first compact normal suite passed six tests and failed three because Check was covered by the keyboard. Scrolling the below-answer actions into view corrected that, but inspecting the largest-text PNG caught the typed line above the viewport despite a weak bottom-edge assertion. The strengthened RED measured editor minY 0 against navigation maxY 116. The editor now uses a two-line minimum at accessibility sizes (without shrinking the font), and the explicit whole-text completion declaration moves into the existing menu. Both editor edges and the complete Check frame are asserted against navigation/keyboard bounds. The earlier normal 9/9 is therefore not final acceptance. One paired keyboard probe was cut short by a tool timeout; its incomplete small-device run is not counted as a pass. Preserved scratch receipts distinguish failures/interruption from the final coherent pair. The v3 small-phone PNG then exposed Check partly under native tabs at ordinary text size. A new actual-viewport RED measured Check maxY 605.5 against tab minY 584.0. The empty editor now starts at four lines (two at accessibility sizes), still grows to fourteen without font reduction, and retains the hierarchy above it. The final suite requires the complete Check frame above tabs before taking the waiting-state screenshot.

Synthetic media/assessment fixtures use real HTTP handlers and persistence with isolated stores, unchanged 30-record cap, generated silent PCM and synthetic inference. They do not establish real speech quality, physical-camera behavior or spoken VoiceOver. The historical budget reconciliation gate remains unresolved and unchanged; this work does not touch ledger data or authorize regeneration.

## Final local verification

The coherent v4 pair passed on the same source manifest, using only the two supplied simulators sequentially: normal dark **9/9**, small light **9/9**, zero failed/skipped UI tests. Each fresh fixture contains 16 records, below the unchanged cap of 30. The cross-tab case retains one controller client, exactly two admitted/stopped listens, cursor zero after explicit Stop, and the original draft. Navigation adds neither admissions nor Stops. Both contrast records stop at four whole-text starts. The completed assessment preserves three planned readings plus one explicit extra replay (four started/four ended) for its first fragment.

Additional executed checks: Go suite/race/vet passed; Swift Core 108 XCTest cases (five existing opt-in skips) and 84 Swift Testing cases; native CI 64 cases (one existing skip); Node 177 cases (176 passed, one existing skip); real native controller/AppModel + Go HTTP 123 tests; legacy policy bridge three tests; Chromium manual-media and assessment flows passed without page errors. No live inference was used. Static added-line security/conflict checks and `git diff --check` are clean; review was local self-review, not an independent reviewer verdict.

`evidence/dictation-compact-local/acceptance.json` records counts, source hashes, button inventories, artifact mappings and protected-file results. Actual waiting views contain only one transport, camera and Check in the task area (nine AX-visible buttons including navigation and four tabs); timeline rows are not buttons. Playing, gap, writing-wait, checked, cross-tab/Back and five-locale maximum-keyboard images are retained for both devices. The final small-phone first viewport now includes the entire Check above tabs, without removing the whole intro or upcoming sentence children.

Clean runtime previews, copied byte-for-byte from final xcresult attachments:
- `evidence/dictation-compact-local/normal/native-manual-fragment-next.png`
- `evidence/dictation-compact-local/small/native-manual-fragment-next.png`

Local-only: no push, deploy, upload, production-account changes or ledger reconciliation. Released Coach source remains `5aa7ad93424640092c3f7a7470936fc20dda9ac2`.
