# Podcasts → activity and starred Coach sources — local candidate

2026-11-22. Branch `candidate/podcast-activity-stars`, isolated worktree `/Users/tinyserve/Projects/KeineMagie-podcast-activity-stars`. Fresh fetch confirms `origin/main` is `9c386eddfb6cff1511b95c8182869ccc3c56db67`, documenting released source `3498ad73168f11e9d3bf172a5011d62018f939d1`. No push, deployment, Apple upload, production mutation, budget change or paid AI/TTS.

## Existing evidence inspected

Podcast worker `completed` meant prepared transcript, not listening. Starred transcript passage groups already supplied exact source IDs/text to Coach; vocabulary status was a different feature, not the requested stars. There was no explicit transcript-study receipt. Existing checked Coach attempts supplied durable completion evidence. This candidate extends those contracts rather than building a player or replacing vocabulary statuses.

## Exact activity definition

- One settled checked exercise whose source is `passage-group:` or legacy `passage:` counts under **Podcasts**, not again under Coach. Correct, incorrect and ambiguous settled checks count; creation, failed/canceled/pending assessment and discussion do not. Rechecks remain one activity, on the original Check date.
- An explicit **Mark transcript studied** action adds one separate completion per retained episode. It is an owner declaration, not measured listening or proof that every sentence was read. Studying an episode and checking one exercise are two distinct activities.
- `PUT /v1/learning/episodes/{id}/studied` with `{}` uses existing auth/CSRF rules and captured `X-Passage-Owner`. Requires an owned completed nonempty transcript. First UTC `studied_at` is immutable; retries/restart/concurrent calls do not add activity. Receipt uses passage-group revision/cache and is also present in podcast coverage. No client-supplied date or owner is accepted.
- Opening, starring, transcription and preparation do not count or trigger generation. No listening claim or player added.
- Existing seven-day API supplies each date, lower-bound count and per-source breakdown using the requested timezone/calendar. Missing/deleted/undated history stays partial, never a verified zero or skill score. Deleting an episode removes its study receipt; an already retained completed Coach exercise remains historical evidence even if its original episode is later removed. There is no lifetime append-only ledger.
- Native and web both expose the explicit control, saved state and activity semantics. Native uses the existing owner-scoped passage-write lifecycle. Web captures the session owner and rejects stale epoch/job results. No new private activity cache.

## Starred exercises

Explicit practice, More and existing daily admission prefer available starred passage groups over general translation/vocabulary sources. Discussion keeps broader context. The exact owner source ID, original text and source/target language pair are retained; interface locale is not the translation target. Existing explicit daily admission policy is unchanged; opening/starring does not call AI.

Podcast cloze and context-translation generation require a meaning-bearing UI-language gloss, not merely a grammar category. Existing leak validation, accepted illustrative alternatives and full-context assessment remain; alternatives are not an exhaustive grading key. Source text and language are revalidated under podcast → learning → auth → coach lock order before publishing generated/assessed work, without holding source locks across inference. Unstar, delete and replacement during inference fail closed. Existing saved exercises are not silently regenerated.

## Verified locally

- Full server `go test -race ./... -count=1`: passed (103.540s); `go vet ./...`: passed after final production changes and replay/activity assertions. Additional import-replacement test cases passed separately under race afterward; production code unchanged.
- Actual Go handlers/stores: explicit study, foreign owner/spoofed payload rejection, concurrent retries, durable restart/readback, deletion, original date/timezone attribution, generation source priority, public clue, contextual alternative, replay dedup and Podcast-only activity attribution. Synthetic provider only. Import replacement is simulated at the locked persisted-store boundary, not claimed as a full import UI test.
- Full Node: 188 pass, 1 skip, no failures. Browser production UI assets with synthetic HTTP: 1280/375 × light/dark, one explicit PUT, persisted reload, no POST/generation.
- Full Swift Core passed, including actual Go study receipt through `PODCAST_STUDY_WIRE_PATH`; 89 Swift Testing tests passed alongside XCTest. Native lifecycle harness and activity integration (2 tests) passed.
- Actual Release UI `testExplicitTranscriptStudyPersists`: 1 passed in each normal/SE × light/dark configuration, 0 failed. Uses real local Go study/activity handlers, asserts one write, cold-relaunch saved state and Podcast count. No simulator clones; both borrowed devices are shut down.
- Earlier feature slices were exercised RED→GREEN (Go semantics/receipt, Swift request/receipt, web owner binding/control and compact native source breakdown).
- Runtime captures in `docs/podcast-activity-stars-evidence/`: native before/saved/detail for four configurations plus four browser captures. Unmodified synthetic-runtime PNGs, not production data. Representative small dark detail and mobile web saved screen inspected: count/control visible, no clipping of detail action. Native full explanatory alert is text-heavy; no physical VoiceOver/AXXXL acceptance claimed for the new prose.

## Reproduction / limits

Run server race/vet; `node --test web/tests/*.test.mjs`; Swift tests in `native/Core`. Browser requires Playwright and `EVIDENCE_DIR`; run `web/tests/podcast_study_browser.py`. Native fixture/test runner follows `native/ci/passage_ui_fixture_test.go` and `PassageGroupsUITests`.

No real provider linguistic-quality measurement, physical-device certification, Safari acceptance or overnight clock observation. Existing controller/drafts/reveal flows are preserved, not redesigned. This is a local candidate requiring preview/product acceptance and separate publication authorization. A future product decision could make completion resettable or introduce full listening coverage; neither is invented here.
