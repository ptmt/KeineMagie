# Episode navigation and learning profile — local verification

## Scope and behavior

Web-only reader/profile implementation; subsequently included in the combined deployed release documented in `COMBINED-WEB-RELEASE.md`. Native and production owner data were not accessed by the local verification task.

- Removed the redundant Overview/statistics/profile wall. Compact episode identity, breadcrumbs, one counts line (pending only when nonzero), quiet private-copy explanation; collection creation/refresh controls stay on the collection.
- Persistent semantic Summary / Words / Recommendations / Transcript links; `aria-current="location"` scrollspy never moves focus. Meaningful query URLs (`section`, stable zero-based `segment`, optional summary `topic`) preserve the clean episode pathname and legacy hash router. Keyboard Enter, Back/Forward, reload and source citation reveal are supported.
- Transcript find searches source and translation across all **2113 synthetic segments**, highlights/counts actual occurrences, offers next/previous/Enter/Shift+Enter and a persistent search toolbar. Timestamp jump uses saved timestamps. Distant matches/citations add only their 100-row chunk rather than constructing all preceding rows; initial 100 rows and unopened quote forms remain lazy. Citation return action and summary topic links use actual analysis data.
- Self-assessed CEFR selector/help/collapsed human-readable dated history moved into existing account dialog’s Learning profile, discoverable via localized Profile button and recommendation-level link. Existing **`/v1/learning/profiles/{de|ru}` GET/PUT** is authoritative (the repository’s actual API is plural, not `/profile`). PUT reads back GET; no duplicate local persistence, automatic promotion or generation. Owner/language epochs reject late results, logout clears private profile DOM; profile errors do not remove episode content or gate analysis.
- DE/EN/RU/ES/FR copy; locale changes retain vocabulary drafts, selection, expanded state and analysis work. No new runtime assets introduced by episode/profile work, CSP unchanged. The concurrent translator child adds its own assets separately.

## Actual design review

Fixed launcher ran **nous / openai/gpt-6-astra / max**, `fallback_model=[]`, with live catalog check before launch. Before and after reviewers actually navigated the local populated synthetic HTTP fixture at desktop **1440×1000** and mobile **320×844** and inspected screenshots via auxiliary vision. Audit wire requests use exact Astra/max; returned labels say Astra. This is not independent upstream serving-model/effort attestation or native Astra vision.

Before findings: section buttons disappeared on scroll, citations did not update history/URL, level/history occupied Overview, transcript lacked find, and account lacked learning profile. After reviewer verified sticky real links/current section, safe offsets, find/citation to segment 2012, Back/Forward/reload, and Profile with collapsed readable dates. It requested reachable find controls, clearer mobile Transcript discovery and quieter pointer focus; those were corrected afterward and checked with targeted real Chromium assertions/screenshots. Collection controls were subsequently removed from episode chrome. The final refinements were not rerun through Astra.

Evidence (local, explicitly synthetic):
- Before: `/Users/tinyserve/.config/browser-harness/tmp/episode-before-{desktop,mobile,mobile-citation,account}.png`.
- Final: `/Users/tinyserve/.hermes/cache/scratch/episode-navigation-evidence/after-{320,1440}.png` and `after-header-{320,1440}.png`.
- Launcher processes/results: `proc_a5e9e3947406` (before), `proc_d52ded0a2d3f` (after), both exit 0, completed audit.

## Executed verification

TDD regression first failed on episode CEFR selector; bounded-chunk regression independently failed before correction; compact collection/Transcript visibility assertions also failed before correction.

- `node --test web/tests/*.test.mjs`: **65 passed**, 0 failed/skipped (includes concurrent translator tests); Node experimental localStorage warning remains.
- `episode_navigation_browser.py`: passed, **31 synthetic HTTP requests**, zero page errors. Semantic/current sticky links, 320px Transcript visibility, collection chrome removal, scroll offsets, topic links, distant find/highlight/count, persistent search, 100-row chunk bound, keyboard/URL/back/reload/citations/return, timestamp, no focus stealing, profile GET/PUT readback, readable collapsed history, profile failure isolation, logout clear, four widths and zero analysis POSTs.
- `episode_browser.py`: passed, latest **71 synthetic requests**, zero page errors: canonical/legacy/cosmetic URL, all global routes/history, 1000 rows / 954 translated / 46 pending, explicit generation fixture, vocabulary/profile readback, exact clipboard permalink, owner clear and four widths.
- `episode_analysis_browser.py`: **7 checks**, zero page errors: no automatic generation, no episode CEFR, vocabulary history, explicit three-step plan, cancel, explicit resume, navigation stop. All provider responses synthetic.
- `i18n_http_browser.py`: **24 checks**, zero page errors. Five locales, open account and quote drafts/selection, no locale network requests, exact history/result data, responsive and guest locale.
- `redesign_browser.py`, `history_preview_browser.py`, `podcast_design_browser.py`: passed, zero page errors. Podcast fixture printed one expected broken-pipe traceback during aborted navigation; browser assertions passed.
- `run_legacy_browser.py`: all **7 suites passed**: browser_smoke 26 checks; directions 19; guest 23; i18n 13; podcasts 41; session 12; styles 13. These legacy eval-only harnesses require the runner, not direct Python execution.
- `env -u TRANSLATION_DAILY_ATTEMPTS go test ./... -count=1`: passed, **29.285s** in combined working tree. `go vet ./...`: passed. `git diff --check`: passed.

## Remaining release gates

Parent coordinated independent combined code review and the release; see `COMBINED-WEB-RELEASE.md` for final deployment evidence. No production inference/deletion/retry was initiated by these verification suites. Synthetic signed-in fixture does not verify genuine owner authentication, live saved private analysis, paid generation or language quality. The independent review subsequently corrected global navigation clipping and verified all four global destinations at 320px in all five locales.
