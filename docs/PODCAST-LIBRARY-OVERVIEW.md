# Podcast library overview — local candidate

## Scope / baseline

Web-only candidate in `/Users/tinyserve/Projects/KeineMagie-podcast-overview`, branch `candidate/podcast-library-overview`. Fresh worktree from fetched `origin/main` **481bb1ca5c5a32d3335862738fc9e5645402d088** (documentation on top of runtime **b3ab6c8b14c5827aef9d903b3a3eb90be51157e8**). No changes to original dirty main, Coach worktrees or AnyProgress. No push, deployment, credentials, private account access, paid inference or TTS.

## Web behavior

- Compact podcast cover/title/optional source author header; header and separate quiet **All episodes / Все эпизоды** link both retain the full-feed route. Episode links are siblings, never nested interactive elements.
- Up to **three latest episodes per podcast**, dated newest first; equal/invalid/missing dates retain stable source order after dated entries. Existing feed metadata retention bound remains 50 episodes; this is not an unlimited remote-feed search. No prioritization by processing activity.
- Episode titles are literal source text. Exact feed/episode IDs identify each row, including identical episode IDs in different feeds. Unprepared title opens `#podcasts/feed/{feed}?episode={episode}`: a focused view of the existing feed action, with explicit Prepare and a full-feed return. Opening never starts preparation. Saved jobs use the existing job route, which resolves to the existing persistent `/podcasts/episodes/{slug}-{digest}` reader URL.
- Actual queued/fetching/transcribing/translating/completed/failed/canceled status, stage progress and existing cancel/retry/delete controls appear on their own episode rows. Stage percentage is not listening progress.
- Coverage is the existing durable `coverage.translated_segments / recognized_segments`, labeled **translated passages** because recognizer segments are not necessarily sentences. The denominator describes saved recognized passages, not a guarantee that recognition has finished. Zero/unknown denominators are omitted. `favorite_passages` is shown separately as **Starred passages**, never vocabulary favorites or playback progress. No analytics or inferred listening state.
- Source author metadata is now parsed from RSS/iTunes author or Atom author/name and persisted by subscription discovery/refresh. Existing subscriptions without author remain valid; no fabricated author and no forced discovery during page opening.
- Same-owner refresh retains the prior DOM rows; keyed reconciliation preserves focused title controls. Initial loading, authenticated empty feed/library, and request failure remain distinct. Existing subscriptions API returns all feed episode arrays atomically; there is no independent per-feed fetch to fail progressively. A failure retains all old rows and displays the existing library error instead of falsely declaring feeds empty. Missing episode arrays show loading, not empty.
- Global Refresh list reloads saved discovery metadata/jobs only. Manual feed discovery remains the existing explicit feed refresh. Neither invokes AI. Explicit Prepare/Retry behavior and reader analysis consent are unchanged.

## API / lifecycle

No new endpoint is required. Existing owner-scoped `GET /v1/podcasts/subscriptions` plus `GET /v1/podcasts` run concurrently (two requests, independent of feed count). The latter already batches real coverage in one owner learning-store read. No per-episode detail requests are added by overview rendering. Existing GET jobs includes transcripts; reducing that legacy payload is outside this candidate.

Additive API metadata: `author,omitempty` on discovery/subscription. Unknown to older clients and safe to omit on older servers. Backend update is needed only to populate authors; inline episode/progress overview uses current API contracts.

Existing 5-second foreground-only active-job polling, 120-round bound, visibility/route pause, abort/epoch owner isolation, expired-session clearing and in-memory-only library are retained. No auth store extraction or browser credential reuse.

## Platforms

- **Web:** implemented and browser-exercised against actual local shipped HTML/CSS/modules with an explicitly synthetic owner/API fixture.
- **iOS:** inspected `native/App/PodcastLibraryView.swift`: subscription NavigationLinks currently show title/latest episode, followed by separate jobs. It does **not** implement inline latest-three episode rows. No native source/cache changes, native builds, UI verification or parity claim.
- Static allowlists, Docker copies, bootstrap, lazy episode module initialization and old-shell compatibility were not changed. Node shell/asset regression tests pass.

## Verification / evidence

- `node --test web/tests/*.test.mjs`: **110 passed**, including new sorting/route tests plus existing owner-race, active polling, CSRF, no-implicit-AI, asset allowlist and older-shell tests. Node emits its existing experimental localStorage warnings.
- `go test ./... -run '^TestPodcast' -count=1`: **passed**. New RSS/Atom author durable-metadata test was observed failing before implementation and passes afterward. Existing owner coverage test proves vocabulary favorites are independent of passage favorites.
- Full `go test ./... -count=1`, `go test -race ./... -count=1` and `go vet ./...`: **passed** during independent review. The former baseline `TestNativeFollowupOptionalOwnerWebCompatibilityAndCSRF` failure was reproduced red, then corrected **only in the test**: `authStore.create("other-owner", …)` takes an Apple subject and returns a different generated `UserID`; the literal subject in `X-Translation-Owner` correctly gets 403 before history lookup. The corrected cases require 404 for absent/matching actual UserID and 403 for mismatched subject, retaining zero upstream calls/quota. No production auth changes.
- `web/tests/podcast_overview_server.py` on loopback **8773**, then execute `web/tests/podcast_overview_browser.py` via browser_exec: **39 checks passed**. Covers delayed initial loading, exactly two batch GETs, per-feed 0/1/3+ episodes, newest sorting, same ID across feeds, literal markup, real coverage/zero denominator, completed/active/failed/canceled states, five locales, 288/320/390/768/1440 CSS-pixel widths, pointer versus keyboard focus, Back, reader URL/reload, focus-retaining updates, refresh/error retention and logout during pending response. The 288px case is the effective layout width of 1440px at 500% zoom; browser chrome zoom itself was not automated.
- Actual public guest inspected at `https://keinemagie.tinyserve.org/#podcasts`: sign-in notice, no private rows, Add disabled. This is current production guest behavior, **not** deployed acceptance of this candidate.
- Actual local browser screenshots (synthetic source data):
  - `/Users/tinyserve/.hermes/cache/scratch/podcast-overview-evidence/overview-1440.png`
  - `/Users/tinyserve/.hermes/cache/scratch/podcast-overview-evidence/overview-390.png`
  - `/Users/tinyserve/.hermes/cache/scratch/podcast-overview-evidence/checks.json`
- Desktop/mobile screenshots independently re-inspected. A real CSS specificity collision between coverage metrics was corrected and a computed-layout-gap assertion added. Independent review reproduced a cramped failed row (160px title column at 390px), added a failing browser assertion, then gave mobile title columns a 220px flex basis so wide action groups wrap beneath readable content. Pointer acquisition has no block outline; keyboard focus still does. No blanket focus suppression was added.

Limits: authenticated production feeds/jobs are not inspected; fixture responses are synthetic, not evidence of live owner data or provider operation. No paid pipeline tested. Candidate awaits parent integration, not release; iOS still has no inline-three overview.
