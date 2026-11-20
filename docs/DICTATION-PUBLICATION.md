# Dictation publication

## Approved scope and preflight

User explicitly approved publication of both web and iOS after the compact preview. Approved product source: `dc607597c42d0ca9aaded1f376ec0c7a8ce06541`; incorporates released native Coach `cff9dee`, web Coach `30d8316`, and release evidence `5aa7ad9`.

Release adds only a focused native optional-final-whole UI test and publication evidence. All production source remains byte-identical to the approved candidate. Compared all 584 entries in `evidence/dictation-compact-local/source-manifest.json`: the sole source difference is `native/UITests/DictationManualUITests.swift`. Existing nine test bodies are unchanged. Read the actual retained normal and small xcresults with xcresulttool: 9 passed / 0 failed / 0 skipped each. Retained offline logs cover Go/race/vet, Swift Core, Node, native CI, policy-1 bridge, real native + Go HTTP 123 cases and synthetic Chromium media/assessment.

Focused previously uncovered native final whole flow now passes on normal dark and small light, sequential existing simulators without clones: 1/1 each. Actual authenticated fixture read-back proves intro + six fragment readings + explicit optional final = eight ended planned listens, two whole starts, final_used=true, explicit complete=true Check, completed assessment, all 12 words attempted/exact. The initial test incorrectly expected Next at the final boundary; source and existing policy tests use the explicit Optional final reading label, disabled after use. Corrected only this new test expectation; kept the failing receipt. No production change.

Fresh native CI: 64 tests, one existing skip, success. Fresh focused Go race suite covers settlement, ten-hold saturation, legacy rejection, oversized ledgers, terminal transport, assessment, pacing, manual integration, replay and owner spend: pass. No paid inference, TTS or owner credentials were used.

## Independent scoped review

Release reviewer is separate from the implementation session. Inspected actual integrated source for immutable assessment binding and exact span quote validation, owner/session fencing, explicit Check and GET-only recovery, persisted pacing/Stop identity, policy-0/1 compatibility, policy-2 manual boundaries and original asset identity, completed-only prospective settlement and owner-attributed spend. No release-blocking concern found in these inspected contracts. This is a scoped source review, not a claim of exhaustive security certification.

The monthly constants remain 10,000,000 microUSD total and 1,000,000 microUSD conservative admission holds. Existing entries without validated settlement remain charged at their original hold; no historical reconciliation path was added. Unknown historical owners remain unknown. Old accounting data must not be edited, forgiven or silently reattributed. Read-only audit `speech-budget-readonly-audit-3afaa52/REVIEW.md` discusses a separate possible legacy-terminal-usage design, not implemented or approved here.

## Deployment boundary

Publication pending at this preflight commit. Backend deploy must precede exactly one native UPLOAD dispatch. Existing production writer is not a safe rollback after new policy-2/assessment/settlement data: recovery must pin this new compatible image, never restart an older field-dropping writer or restore historical data. Preserve byte-identical nonruntime durable files under store/account locks and maintenance, including the actual current ledger; use current aggregates, never stale counts.

Protected original manifests verified: KeineMagie 304 files and AnyProgress 13 files, zero mismatches. No AnyProgress data or pending work modified. Both borrowed simulators shut down after the focused test; no local simulator reservation is retained for hosted CI.

Synthetic audio/assessment proves lifecycle, receipts and UI, not production speech quality, real owner inference or physical-device behavior. Existing audio-session activation runtime warning remains. Historical budget holds can still block preparation after this release; publishing prospective accounting does not unblock old holds.
