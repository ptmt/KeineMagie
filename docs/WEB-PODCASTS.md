# Web podcasts

The `#podcasts` placeholder is now the authenticated library using the existing owner-scoped podcast API. All runtime code remains in the already-allowlisted and Docker-copied `app.mjs` / `core.mjs`; no server changes or new public asset paths are required.

## Behavior

- Compact cover/title/latest-episode list; top-right `+` opens feed subscription or individual episode import. Subscriptions and manual feed refresh only discover metadata; they never start AI work.
- Feed routes: `#podcasts/feed/{encoded-id}`. Explicit episode preparation sends **only** `{feed_id, episode_id, source_language}` to `POST /v1/podcasts`. The server owns enclosure identity and idempotency. Per-owner/feed/episode in-flight submissions coalesce to one request.
- Podcasts default to **de → ru** independently of the translator's existing **ru → de** default. Feed view and individual import offer ru → de too.
- Job routes: `#podcasts/job/{encoded-id}`. Render actual queued/fetching/transcribing/translating/completed/failed/canceled state. `completed` is displayed as “Bereit”. Progress is server stage/batch progress, not invented recognition or playback progress. Transcript reader uses returned start/end/text/translation; no fake player or external-media fetch.
- Artwork is an ordinary same-origin image at `/v1/podcasts/subscriptions/{id}/artwork`, selected solely by the stored feed ID; external `artwork_url` is never loaded by the browser. No session/token inspection or bearer storage.
- Explicit cancel/retry/delete and unsubscribe; destructive delete/unsubscribe require confirmation. Mutation handlers read back the job or library before presenting the resulting navigation. Errors distinguish source restrictions, authorization, unavailable preparation and quota/rate limits.
- Initial skeleton, first-load failure, authenticated empty and guest states are distinct. Refresh keeps existing library data on failure. Direct-import section appears only when actual unlinked jobs exist; server feed/episode/preparation associations prevent anonymous feed duplicates.
- Cookie-authenticated same-origin requests; mutations carry session CSRF. Guest controls are disabled, with existing official Apple artwork before any ChatGPT setup. Owner change, expiry and logout abort requests, increment a generation guard, close/clear import fields and synchronously remove private podcast DOM. No podcast localStorage/cache.
- One 5-second foreground polling chain while podcast route is visible and jobs are active, at most 120 rounds per activation (10 minutes). Stops on route exit, hidden tab, logout, errors or settled jobs. Visibility return rechecks the session before resuming; refresh explicitly restarts the bound. No automatic feed refresh.
- Translator DOM/draft/history/style handling is preserved across section navigation.

## Verification

`node --test web/tests/*.test.mjs` exercises real API client cookie/CSRF/request shapes, owner/generation races, coalescing, polling cap and existing account/style/direction behavior.

Browser fixture:

1. From the repository: `python3 web/tests/podcast_fixture_server.py` (localhost:8769; real shipped assets and an explicitly synthetic green checkerboard cover).
2. With browser_exec helpers, execute `web/tests/podcasts_browser.py`.
3. The fixture intercepts `/v1/` with synthetic owner/feed/job data. It checks real shipped HTML/CSS/JS under the shipped CSP and captures 320/1440 screenshots. Visibility is explicitly simulated because background browser tools report hidden tabs. No provider credentials or live inference are involved.

Evidence: `/Users/tinyserve/.hermes/cache/scratch/keinemagie-podcast-evidence/` (`checks.json`, library/reader screenshots, add-dialog screenshot). Existing guest/directions/styles browser fixtures also load the full current app and remain regression checks.

## Reviewed deployment — 2026-11-11

Independent review checked owner/generation abort boundaries, bounded foreground polling, cookie/CSRF transport, actual Go method/status/payload contracts, metadata-only subscription/refresh, same-origin artwork proxy, textContent-only transcript rendering, and server-side durable identity before recognition/provider admission. No release-blocking implementation defect was found.

- Node: **40 passed**. Real shipped-assets podcast browser fixture: **39 checks**, plus guest **23**, directions **18**, styles **13**. Mobile library/reader screenshots inspected. One combined guest run hit a fixed-delay timing assertion; isolated rerun passed all 23 (fixture timing limitation).
- Deployed backend image: `sha256:7f037ed2956a3199cd701751b6e29a4795e0384ccf503f5cf762dbe0648818fa`. Rebuilt the actual backend/static-assets image from the reviewed tree with network-disabled build steps; changed only the existing durable override's exact prior backend pin (`cdaf691d6c1f…`). Worker `44b2fccc4df1…`, unrelated container IDs, resource/security configuration, mounts and network membership unchanged.
- No active jobs or held translation quota locks at preflight. Locked private backup retained; all **6 non-runtime persisted files byte-identical** afterward, including auth/provider/history/podcast state. Counts: **1 user / 2 sessions / 0 jobs / 1 subscription**. No account or provider data was synthesized or altered.
- Public certificate-validating HTTPS: `/health` **200**; `/v1/web/session`, `/v1/podcasts`, `/v1/podcasts/subscriptions` **401**. Actual live browser loaded `#podcasts`, displayed Apple sign-in guidance instead of “Noch nicht verfügbar”, kept add/refresh disabled, and exposed no ChatGPT setup before identity sign-in. Shipped modules/CSS returned **200** with no-store headers.
- This is the documented manual backend-only Compose lifecycle, not automatic tinyserve/registry deployment. See [deployment/rollback](DEPLOYMENT.md).

**Still unverified:** real signed-in owner journey, Apple web consent/account match, and actual user episode → Whisper → personal-provider translation. Synthetic fixture authorization is not real-account acceptance. No paid inference, credentials reuse, seeding, worker restart or native change was performed. This web/docs-only push matches server publication paths, not iOS TestFlight paths.
