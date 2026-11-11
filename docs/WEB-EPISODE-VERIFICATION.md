# Episode UI and private permalinks

## Contract

- Canonical URL: `/podcasts/episodes/{cosmetic-title-slug}-{suffix}`.
- `suffix` is the first 12 lowercase hex characters of SHA-256 of the **exact UTF-8 existing job ID**. The opaque ID is never lowercased, shortened, repaired, or used as a bearer credential.
- `GET /v1/podcasts/episodes/{slug}-{suffix}` uses existing podcast authentication, loads only the authenticated owner's jobs, matches the suffix independently of the slug, and returns 404 for zero or ambiguous matches. Responses are `no-store`.
- Deep HTTP GET/HEAD returns only the normal public application shell, with no episode metadata. All static asset paths are root absolute, CSP remains same-origin/no inline script, and runtime module files are explicitly allowlisted/copied in Docker.
- Legacy `#podcasts/job/{exact-id}` routes resolve authenticated details before `replaceState` canonicalization. `popstate` handles clean-path history; all original hash tabs remain usable from nested paths.
- Copy uses the real Clipboard API and explicitly says the link requires the viewer's own authenticated account, not public sharing.

## Reader

`web/episode-view.mjs` integrates the sibling's `EPISODE-LEARNING-API.md` contract: cached analysis GET, explicit one-request Generate/Continue POST, source-validated citation jumps to actual segment IDs, quote-based server favorites/word/idiom saving, independent saved/learning/known state, profile PUT with self-assessed unknown/A1–C2, and actual server vocabulary counts. Mutations read back server state. Identity changes abort/coalesce requests, discard late responses, and clear private memory/DOM. No paid inference is automatic.

Saved ASR rows render while jobs run; translated rows are shown immediately and remaining rows explicitly await translation. No stage percentage masquerades as audio/translation progress.

Episode copy lives in `episode-i18n.mjs` and uses the shared `getInterfaceLanguage()`; the i18n sibling supplied all five language dictionaries and draft-preserving locale refresh.

## Verification

- `go test ./... -count=1`: passed (28.223s in the integrated working tree).
- `node --test web/tests/*.test.mjs`: 57 passed; Node prints its experimental localStorage warning.
- Browser: `/Users/tinyserve/.hermes/cache/scratch/episode-browser-venv/bin/python web/tests/episode_browser.py` passed with 63 explicit synthetic HTTP requests and zero page errors.
- Browser assertions: legacy replacement, direct clean HTTP URL, cosmetic slug changes, clean-path popstate and hash back/forward, all navigation tabs, 1000 saved ASR / 954 translated / 46 pending rows, explicit analysis only, real citation focus, server profile/vocabulary readback, real clipboard contents, logout clearing, and no horizontal overflow at 320/390/768/1440.
- Screenshot inspected: `/Users/tinyserve/.hermes/cache/scratch/episode-evidence/reader-1440.png`.
- No real account/provider inference, production mutation, commit, push, or deployment. Browser fixtures are explicit synthetic data, not proof of live provider execution.

## Remaining integration checks

The sibling backend was written concurrently. Its full Go suite passed; this UI's learning interactions were exercised through a synthetic same-origin HTTP contract server, not a real logged-in provider. A live authenticated end-to-end check should be performed only with separate consent for any paid analysis request.
