# Independent episode/profile review (combined uncommitted tree)

Local synthetic fixtures only. No private production data, provider inference, native edits, commit, push or deployment. Follow-up/server files were inspected only as shared context and not changed by this reviewer.

## Findings corrected (test failed first)

- **Global route clipping:** Coach was outside its navigation viewport at 320px; German also clipped at 768px. Scoped `.topbar .section-nav` wrapping and a four-column narrow layout keep all four routes, including unavailable notices, visible without page overflow.
- **Citation return lost its source:** Back to section focused only the section heading. Citation controls now have deterministic render IDs; return restores the originating citation (including a topic citation), not whichever heading scrollspy happened to select.
- **Timestamp gaps chose the next segment instead of nearest saved range:** Added tested `transcriptTimeIndex`; preserves zero, selects a containing range or nearest range boundary, ignores invalid saved timestamps, rejects malformed/unsafe input and handles empty transcripts.
- **Sticky toolbar assumed 53px navigation:** A forced wrapped-navigation browser regression failed. A ResizeObserver and synchronous jump measurement now share actual nav height through CSS custom properties with toolbar/heading offsets.

## Exact reviewer edits

- `web/episode.css`
- `web/episode-view.mjs`
- `web/episode.mjs`
- `web/tests/episode.test.mjs`
- `web/tests/episode_navigation_browser.py` (return-focus expectation)
- `web/tests/episode_review_browser.py` (new independent real Chromium suite)
- this report

Existing app/account/i18n and concurrent follow-up changes remain intact.

## Security and isolation

Reviewed account profile request epoch, authenticated owner and profile language checks around PUT and GET/readback. Browser delayed-response regressions actually replace owner while GET is pending and log out with a second GET pending; neither late response restores prior CEFR/history. Opening/profile locale changes produce no PUT. API stays exactly plural `/v1/learning/profiles/{de|ru}`; no browser profile persistence or automatic promotion.

Section values are allowlisted, segment indices validated before selectors, topic selectors accept digits only; URL construction uses same-origin pathname/search/hash and URLSearchParams. Browser tested encoded markup, unsafe/out-of-range segment and topic values, an external `next` query, valid segment reload and Podcasts hash return. No script/image injection or redirect occurred. Transcript/provider strings render via text nodes; literal `<script>` stays literal. No automatic analysis POST occurred.

## Verification and evidence

- `node --test web/tests/*.test.mjs`: 67 passed, 0 failed/skipped in combined tree; existing experimental Node localStorage warning.
- New `episode_review_browser.py`: passed, 83 synthetic requests, zero page errors. Five locales × 320/390/768/1440 keyboard navigation; all four global labels contained; 2113-match counter despite only bounded mounted rows; no hidden quote forms; no-match controls; forced wrapped sticky offset; stable citation return; zero/invalid timestamp; quote draft/selection retained across locale changes without scrollTo replay; delayed owner/logout GET; encoded queries/hash route; empty/missing analysis; vocabulary failure; partial untranslated transcript; literal markup; no automatic PUT/analysis.
- `episode_navigation_browser.py`: final rerun passed, 31 synthetic requests, zero page errors. `redesign_browser.py`: final rerun passed, zero errors.
- `episode_browser.py`: passed, 70 requests, zero page errors; `episode_analysis_browser.py`: 7 passed; `i18n_http_browser.py`: 24 passed, zero page errors.
- `git diff --check`: passed.
- Actual screenshot inspection via vision: `/Users/tinyserve/.hermes/cache/scratch/episode-independent-review/after-en-320.png`, `after-fr-320.png`, `after-fr-1440.png`. All four global destinations visible; no page overflow. Ten screenshots (five locales, 320/1440) stored in that directory. Vision's numeric transcript timestamp transcription and comparison-width explanation were inaccurate; DOM/browser assertions, not those claims, are authoritative.

No remaining blocking finding in this inspected episode/profile scope. Synthetic authentication is not a live-owner/server authorization test. Release still belongs to parent after both independent reviews; no follow-up release endorsement is implied here.
