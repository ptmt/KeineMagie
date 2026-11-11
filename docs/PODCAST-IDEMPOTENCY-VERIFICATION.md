# Podcast import idempotency verification

## Contract

- Owner + source language + server-owned feed/episode identity identify a preparation. Different episode GUIDs sharing audio remain distinct. Legacy enclosure imports attach to a feed only when that enclosure has one unambiguous owner-owned episode.
- Existing retained preparations return HTTP 202 before worker readiness, provider credentials/catalog, and budget reservation. Completed preparations win over obsolete queued duplicates. Existing failed/canceled jobs do not implicitly retry.
- Concurrent first imports recheck identity and perform admission inside the durable store lock: one reservation and one worker-readiness probe, no provider/catalog or source calls for known feed/direct-media URLs. No owner-provider lock is taken beneath this store lock (translation takes the opposite order).
- Obvious media suffixes skip metadata discovery, not worker URL/DNS/redirect/MIME/size validation. Unknown URLs/HTML require the hardened bounded resolver. A previously validated page alias survives source outages. Previously unknown HTML can require fetching the page to establish its media identity, but never a provider request.
- Historical page aliases reconcile only when the exact same supplied source is known. Never infer identity from title, path similarity, stripped query parameters, or another owner's data; live claim input is not rewritten. An old page-only record cannot be associated with an unrelated enclosure without evidence.
- Historical queued twins are retained, made terminal failed with an explanatory duplicate message and zero new attempts, not deleted. They cannot linger queued forever or automatically rerun after canonical failure. Explicit retry remains an intentional action. Completed results and live claim fencing remain intact.
- Explicit deletion removes the retained identity; a subsequent import is allowed as a new job and consumes a new reservation. No tombstones are introduced.
- Authentication, owner isolation and browser Origin/CSRF checks precede idempotency. No production auth probes or real-job mutations were performed.

## Synthetic local HTTP evidence

`podcast_http_identity_test.go` uses real simultaneous HTTP POSTs with fixture-owned sessions and counter-backed worker/provider/source transports. New import: 20 responses share one ID, one retained job, one daily reservation, one readiness call, zero provider calls, zero source calls. Repeat after reopening the durable store preserves the ID. Existing-job fixture: 24 simultaneous HTTP responses across two service/store constructions share the existing ID despite unavailable worker/provider, with zero upstream calls and unchanged budget. Security cases cover guest, foreign subscription owner, absent CSRF, foreign Origin, and accepted browser mutation.

Additional regression tests cover canceled explicit retry, post-delete reimport, exact historical source reconciliation, direct-media discovery avoidance, completed-preparation preference, and historical twin claim suppression including canonical failure.

## Production audit (read-only snapshot)

Discovered live `tinyserve-keinemagie-1` mount `keinemagie-data` at `/app/data`, with effective `HISTORY_PATH=/app/data/history.json`. `newPodcasts` in `podcast_worker.go` constructs `filepath.Join(filepath.Dir(cfg.historyPath), "podcasts", "jobs.json")`; there is no independent `PODCAST_PATH`/`PODCAST_STORE_PATH` override. Thus the authoritative path is `/app/data/podcasts/jobs.json`. Re-read the mounted directory with `docker cp ... -` into an in-memory tar reader and required actual `jobs` (array) and `budgets` (object) keys, rather than treating an absent/wrong file as empty.

Observed later pre-release snapshot: **0 jobs, 1 subscription, 0 active jobs, 0 exact same-owner media/source-language groups and 0 duplicate groups**. The private **previous long-release backup really contains 2 jobs** in this same logical store. These are different snapshots; the cause of the intervening change is not established. This release neither deletes nor restores jobs, and never manually mutates the database. An empty current snapshot does not prove historical duplicates never existed or resolve unproven page/enclosure aliases. All current files are preserved; post-deployment hashes are compared without exposing record contents or credentials.

## Verification commands

- `go test -race -json ./...` (full Go suite, including existing browser/CSRF tests; opt-in external/real-tool tests may skip).
- `go vet ./...`
- `git diff --check`
- `go test -race -run 'TestPodcastHTTP|TestPodcastClaimRetainsDuplicatesWithoutRerun' -count=10`

Full run: **293 test/subtest passes, 4 opt-in skips** (**129 top-level passes, 4 skips**); `go vet ./...`, `git diff --check`, and the targeted race suite repeated 10 times all pass. Existing browser/CSRF test passes include Apple web start, browser provider bootstrap, history browser mutations, browser pairing tracer, and podcast feed browser CSRF; the new podcast existing-job security cases also pass. Skipped opt-ins: local interactive browser harness, real remote recognition container, real local Whisper, provider authorize diagnostic. No real browser/provider/recognition claim is made here.

Full run evidence: `/Users/tinyserve/.hermes/cache/scratch/km-idempotency-go-race.json`. These are local candidate tests, not a deployed release or real provider/recognition benchmark.
