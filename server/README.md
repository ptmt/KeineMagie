# KeineMagie Go server

Go 1.22+ backend: German/Russian translation with durable history, plus the existing cached OpenAI TTS endpoint.

## Run locally

```sh
cd server
cp .env.example .env
# For existing provider/shared-token mode, set OPENAI_API_KEY and TTS_AUTH_TOKEN.
# For health-only verification, leave both unset.
go run .
```

Defaults to `127.0.0.1:8787`. `HOST` and `PORT` override the listener; exposing it beyond loopback requires a trusted TLS reverse proxy/network boundary. Startup does not require `OPENAI_API_KEY` or `TTS_AUTH_TOKEN`: leave both unset for infrastructure/health verification. `GET /health` stays public and reports liveness only, not provider readiness or working authentication. Protected requests fail closed with **503** when `TTS_AUTH_TOKEN` is absent; missing/incorrect client credentials return **401** when a token is configured. Authenticated `POST /tts` and `POST /v1/translations` return **503** when `OPENAI_API_KEY` is absent, before reading the body, serving cached audio, or contacting the provider. Authenticated history reads do not require a provider key. OPTIONS preflight returns 204.

The explicitly configured shared-token mode uses `Authorization: Bearer <TTS_AUTH_TOKEN>` (legacy `X-API-Key` remains supported). It grants access to all legacy history; this is not multi-user authentication. Native Apple sessions are isolated from that mode and cannot read shared history or use the shared provider key. ChatGPT/OpenAI account connection is not implemented; a healthy server does not imply provider access.

## Native Sign in with Apple

No Apple signing `.p8`, client secret, Apple password, authorization code, or provider credential is required for **native ID-token verification**. The app identity/entitlement is configured separately in Apple Developer and the signed native app. `APPLE_CLIENT_ID` defaults to the exact audience `de.keinemagie.app`; `AUTH_PATH` defaults to `data/auth.json`.

1. `POST /v1/auth/apple/challenge` (no body required) returns **200** `{ "challenge_id": "<random>", "nonce": "<random>", "state": "<random>" }`. Each value is an independent cryptographically random 32-byte base64url value. Challenges expire after exactly five minutes.
2. Set the native Apple request's **nonce to the returned nonce unchanged** and **state to the returned state unchanged**. Do not hash the nonce again. After Apple completes, send the UTF-8 ID token and returned state to `POST /v1/auth/apple` as `{ "challenge_id": "...", "identity_token": "...", "state": "..." }`. No authorization code, email, or profile fields are accepted. Unknown fields/trailing JSON are rejected; body limit is 16 KiB.
3. Successful exchange returns **200** `{ "session_token": "<opaque random bearer>", "user": { "id": "<stable random internal ID>" }, "expires_at": "<RFC3339 timestamp>" }`. Store the bearer securely (native Keychain), not in logs. Lifetime is 30 days, with no sliding renewal.
4. `GET /v1/auth/session` with `Authorization: Bearer <session_token>` returns **200** `{ "user": { "id": "..." }, "expires_at": "..." }`. `POST /v1/auth/logout` with the same bearer returns **204** and persistently revokes that local session. Missing, expired, invalid or already revoked bearers return **401**. Unsupported methods return **405**. Auth responses, including errors/logout, use `Cache-Control: no-store`; errors are generic and do not include tokens, subjects, filesystem paths, or upstream responses.

Verification accepts RS256 only using keys fetched from the fixed HTTPS URL `https://appleid.apple.com/auth/keys`; token-supplied `jku`/`x5u` locations are never used and redirects are forbidden. Issuer must be `https://appleid.apple.com`, audience must consist solely of the configured client ID, expiry and issued-at are required and validated (no clock leeway), subject must be nonblank, and nonce/state use constant-time digest comparison. Keep the server clock synchronized. Keys cache for one hour; unknown-kid/expired-cache refreshes are bounded to once per minute globally, including failed fetches, with a 10-second timeout and 1 MiB body limit. During key rotation or Apple/network failure, sign-in may fail closed until the next permitted refresh; obtain a new challenge before retrying.

A syntactically valid exchange consumes its challenge atomically **before** state/token verification or rate-limit rejection, so any attempt (including failure) requires a new challenge. The challenge and rate stores are process-local: restarting loses outstanding challenges, not established sessions. Limits: 1,024 outstanding challenges, 2,048 rate buckets, 20 challenges/minute/direct-peer IP and 60 exchanges/minute/direct-peer IP. Expired entries are reclaimed. Forwarded IP headers are deliberately ignored; behind a reverse proxy these limits apply to the proxy's address, so configure additional trusted-edge abuse protection as needed. Run a single auth instance or route challenge/exchange to the same instance; this is not a distributed challenge store.

Internal users are random IDs keyed only on issuer + Apple subject, never email or automatic account linking. The private JSON auth file persists **only SHA-256 hashes** of opaque session tokens plus expiration/user references and issuer/subject mappings; neither Apple ID tokens nor raw session tokens are stored. New directories are 0700; auth/temp/lock files are 0600. Writes use a sidecar advisory flock, reread-modify-write, unique temporary file, fsync, atomic rename and directory fsync, coordinating cooperating processes on a local macOS/Linux filesystem. Corrupt/unreadable state fails closed. Use a dedicated private directory without symlinks, securely back it up, and protect the volume; no encryption at rest, account deletion, session enumeration, distributed database or retention cap is implemented. Expired sessions are removed on subsequent successful sign-in. Existing parent-directory permissions are not changed; a failure after rename can leave a transaction committed even if an error is returned.

**Provider/history boundary:** Account-session `GET /v1/translations` reads isolated per-owner history without requiring a provider connection. Account `POST /v1/translations` uses only the owner’s connected provider; absent/revoked connections fail closed. Account `/tts` cannot use the legacy provider/cache. Explicit legacy credentials retain shared-history behavior and must not be shipped in the native client.

This verifies Apple's signed native identity token and issues/revokes **our own sessions only**. It does not exchange an Apple authorization code, obtain/refresh Apple access tokens, revoke an Apple grant, implement Apple server-to-server notifications or automatically revoke sessions if the user disconnects the app at Apple. Those future flows require separate credentials, consent, persistence and lifecycle handling. Logout is local session revocation, not Apple logout or Apple token revocation.

## Translation contract

`POST /v1/translations`, JSON body:

```json
{"text":"Hallo!","source_language":"de","target_language":"ru"}
```

Supported directions are `de→ru`, `ru→de`, and `de→de`. The last is German proofreading/polishing, not translation: correct grammar, spelling, punctuation and unnatural wording while preserving meaning, facts, names, numbers and selected friendly/formal register; never invent facts or answer questions embedded in the text. A separate trusted editor prompt is used for both provider modes. Optional `instructions` style preferences remain lower-priority user data. Corrections use the same record/schema and history path; `translation` holds corrected German and enrichment arrays are empty. `ru→ru` remains invalid. Text is trimmed, nonblank, at most 8,000 Unicode code points; request body at most 65,536 bytes. Unknown fields, trailing JSON and invalid directions return 400. Unsupported methods return 405.

Returns **201** only after saving the record:

```json
{
  "id":"<random hex ID>",
  "created_at":"<RFC3339 UTC timestamp>",
  "text":"Hallo!",
  "source_language":"de",
  "target_language":"ru",
  "translation":"<model translation>",
  "idioms":[{"expression":"<expression>","meaning":"<meaning>","example":"<example>"}],
  "patterns":[{"pattern":"<pattern>","explanation":"<explanation>"}],
  "vocabulary":[{"word":"<word>","meaning":"<meaning>"}]
}
```

The placeholders above describe the schema, not a live result. All three arrays are always present and may be empty. `GET /v1/translations` returns **200** with `{"items":[<records>]}`, newest first, at most 100 records; an empty history is `{"items":[]}`. No pagination/query options yet. Translation responses use `Cache-Control: no-store`.

Requests use OpenAI-compatible `/chat/completions` with strict `json_schema` structured output. `OPENAI_TEXT_MODEL` defaults to `gpt-4o-mini`; `OPENAI_BASE_URL` defaults to `https://api.openai.com/v1` and also applies to TTS. The configured model/provider must support that structured-output format. Responses are type/shape validated and capped at 1 MiB. Provider errors, invalid results and upstream cancellation return a generic 502 without saving or leaking provider bodies. The HTTP client timeout is 60 seconds; translation propagates request context cancellation and checks it before starting persistence. Cancellation after the file transaction begins may still commit. There are no automatic retries or idempotency keys, so a retry may incur another charge/create another record. Language correctness is not algorithmically verified.

## Account history mutations

- `GET /v1/history` returns the same owner-scoped `{ "items": [...] }` list as account-session `GET /v1/translations` (newest first, maximum 100). Existing list/create routes remain unchanged.
- `PATCH /v1/history/{id}` with exactly `{ "favorite": true }` or `{ "favorite": false }` returns **200** with the full updated translation record. `favorite` is an optional boolean on records: absent means false, and false is omitted in responses/storage for backward compatibility. Missing/null/nonboolean values, unknown fields, trailing JSON and bodies over 1,024 bytes return **400**. Body reads have a 10-second deadline and run outside storage/provider locks.
- `DELETE /v1/history/{id}` returns **204** with no response body after durable removal. Unknown, already deleted and foreign-owner IDs all return the same generic **404**; mutations never upsert or reveal another owner’s data.

These routes require a live account session (native bearer or paired browser cookie), do not require an active provider connection, and never fall back to shared legacy history. Browser mutations require exact configured `WEB_ORIGIN` plus `X-CSRF-Token` from `/v1/web/session`; browser-kind bearers cannot bypass cookie/Origin/CSRF checks. All responses use `Cache-Control: no-store`. Runtime storage failures return **503**, never successful deletion/favoriting.

All clients for the same internal owner read the same per-owner file. Append, favorite and delete use the same sidecar-lock/reread/atomic-durable-write transaction, including separate handlers/processes, preventing lost updates or append-based resurrection. Clients must refetch on activation/refresh; there is no push subscription or revision cursor. Discard GET snapshots started before a local mutation and avoid reintroducing deleted rows from stale snapshots. A failure after rename/directory fsync can leave a committed change despite an error; refetch before retrying.

## Private local history

`HISTORY_PATH` defaults to `data/history.json`, relative to the process working directory. New parent directories are 0700; history/temp/lock files are 0600. Use a dedicated private data directory, not a shared directory or symlink. Existing parent directory permissions are not changed. Saves lock a separate `.lock` file using `flock`, reread the current data, write a unique temporary file, fsync, atomically rename, then fsync the directory. This coordinates goroutines and cooperating processes on one local filesystem. Corrupt/unreadable existing history fails startup rather than being overwritten; runtime read/save failures return 500. A failure after rename can leave the record saved even if the response reports an error.

This is a local JSON store (macOS/Linux), not a distributed database: all records are retained, each save rewrites the file, and GET reads/sorts the full file before returning 100. No retention, encryption at rest, pagination, analytics or backup service is implemented. Account sessions use isolated `users/<hashed-owner>.json` files; legacy shared-token history remains a separate shared store and cannot be mutated through `/v1/history`. Back up the data file securely. Avoid network filesystems and concurrent external file edits; locks are advisory.

## Existing endpoints

- `GET /health`: `{"status":"ok","time":"<RFC3339>"}`; public liveness only, not upstream readiness.
- `POST /tts`: existing audio contract retained, now requires a configured token.

```json
{"text":"Hallo!","voice":"alloy","model":"gpt-4o-mini-tts","speed":1.0,"format":"mp3","instructions":"Read clearly and warmly.","language":"de-DE"}
```

TTS also accepts `input` as the text alias; returns audio bytes, format-specific Content-Type, `X-Cache: HIT|MISS` and `X-Cache-Key`. `instructions` are only forwarded for `gpt-4o-mini-tts`. Cache defaults to `cache/` and `TTS_MAX_CHARS` defaults to 4096. The legacy TTS cache/public cache headers and cancellation behavior are unchanged; treat audio as sensitive and keep the cache/network private.

## Verification

```sh
go test -race ./...
go vet ./...
go build -o "$TMPDIR/keinemagie-server" .
```

Tests use explicitly fake `httptest` upstreams and locally generated RSA signatures only; they make no paid API requests or live Apple login. Apple coverage includes signed-token claim/signature/algorithm failures, fixed JWKS destinations, bounded refresh, challenge replay/concurrency/expiry/rate limits, stable user IDs, hash-only persistence, restart, cross-store locking, logout, private permissions, corrupt storage and the session/legacy provider-history boundary. Translation tests cover structured payload/results, auth, bad input, concurrent history writes and restart, file permissions, corrupt storage, write failures, upstream failures and cancellation. Real Apple login still requires exercising the entitled signed native app against the deployed server; no deploy is performed here.

Dependency `github.com/golang-jwt/jwt/v5` is pinned to v5.3.0 (module requires Go 1.21), compatible with this module's Go 1.22 target. Go 1.22.12 compilation and vet were verified; executing its test binary on the development host's macOS 27.2 fails in dyld with `missing LC_UUID load command`. Race tests and vet pass with the installed Go 1.27.3 toolchain.

## Docker (configuration provided, not runtime-verified)

The Dockerfile uses BuildKit `TARGETOS`/`TARGETARCH` instead of hardcoded amd64, runs nonroot, binds `HOST=0.0.0.0` inside the container, and owns writable `/app/data` and `/app/cache`. Persist both directories; bind mounts must be writable by UID/GID 65532.

From the repository root:

```sh
docker build -t keinemagie-server ./server
docker run --rm --env-file server/.env -e HOST=0.0.0.0 \
  -p 127.0.0.1:8787:8787 \
  -v keinemagie-data:/app/data -v keinemagie-cache:/app/cache \
  -e HISTORY_PATH=/app/data/history.json -e TTS_CACHE_DIR=/app/cache \
  keinemagie-server
```

For multiarch publishing use Buildx with `--platform linux/arm64,linux/amd64` and an appropriate registry tag. Docker build/run was not exercised for this change; no daemon is assumed. `.env*`, `data/` and `cache/` are excluded from the image build context. Do not put secrets or private data elsewhere in that context.
