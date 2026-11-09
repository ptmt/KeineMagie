# Local deployment: prepared, NOT transitioned

## Review gate / current state (2026-11-09)

Public hostname remains `https://keinemagie.tinyserve.org`. The existing container
`tinyserve-keinemagie-1` still runs **`keinemagie:local`** with its original container
ID `4001f248329fc779a0fe51e075fb199d2efafdcc55c29ca5218713b1898ad609` and
start time `2026-11-08T15:11:01.073532429Z`. No application container was started,
recreated, stopped, or exposed during this preparation. No DNS, tunnel, tinyserve
registration, or global provider credentials were changed or used. No paid provider,
translation, OAuth, or TTS calls were made.

Preparation read the real persistent auth store without printing identities or
session values: **1 user and 1 session exist**. Auth bytes were identical before and
after preparation. This supersedes older notes claiming no users or persistence.

## Persistent storage and exact defaults

Existing named Docker volumes are retained, not replaced:

| Mount | Volume / path | Runtime owner / mode |
| --- | --- | --- |
| `/app/data` | `keinemagie-data` | 65532:65532 / 0700 |
| `/app/cache` | `keinemagie-cache` | Existing volume; UID 65532 write access verified |
| `/app/data/auth.json` | `AUTH_PATH` explicitly set; code default `data/auth.json` | Existing 0600 file, unchanged |
| `/app/data/history.json` | `HISTORY_PATH`; Docker image already defaults here | Created on first history save; lock already exists |
| `/app/data/providers` | Derived from directory of AUTH_PATH; **no provider-dir env** | 65532:65532 / 0700 |
| `/app/data/providers/quotas` | Derived from provider dir; **no quota-path env** | 65532:65532 / 0700 |

Provider encrypted files (`*.enc`), host identity (`host`), and quota counters/locks
persist under these directories. `TRANSLATION_DAILY_ATTEMPTS=100` explicitly retains
the code default. Only the data root mode was tightened from 0755 to 0700; auth
contents and existing account/session state were preserved. No history was invented.

## Encryption key: outside repository and separate from data

- Host retained key: `/Users/tinyserve/Library/Application Support/tinyserve/secrets/keinemagie/provider.key`
- Host parent: mode 0700; key: current macOS owner, mode 0600, **32 raw random bytes**.
- Generated with Python `os.urandom(32)` using exclusive, no-follow creation; existing
  files are never overwritten. No key material was printed.
- Docker runtime copy: named volume **`keinemagie-provider-key`**, `provider.key`,
  owner **65532:65532**, mode **0600**, containing the same bytes (comparison only;
  no secret output). Volume root: 0700, owner 65532:65532.
- Intended runtime mount: **read-only** at `/run/keinemagie-secrets`.
- `PROVIDER_KEY_FILE=/run/keinemagie-secrets/provider.key`.

The runtime copy avoids macOS bind-mount ownership ambiguity for a nonroot
container. The retained host key and runtime key are separate from provider data.
UID 65532 was tested with a network-disabled utility container: key readable,
key mount not writable, auth readable, data/provider/quota/cache directories
writable. That utility did not run the application or call providers.

**Back up the key separately and securely before real provider consent.** Loss of
both copies makes encrypted provider credentials unrecoverable. Never remove or
rotate this key as part of a routine container rebuild, `down -v`, or migration.
FileVault was reported **OFF** by `tinyserve checklist`; owner-only permissions are
not at-rest disk encryption. No off-host encrypted key backup was created here.

## Durable override and image

Prepared durable Compose override (not auto-applied):

`/Users/tinyserve/Library/Application Support/tinyserve/services/keinemagie/deployment/compose.translator.yml`

It explicitly sets image `keinemagie:translator`, `pull_policy: never`, user
`65532:65532`, `WEB_ORIGIN=https://keinemagie.tinyserve.org`, auth/history/cache
paths, key path and daily limit. Existing data/cache and new key volumes are
**external**, preventing accidental silent creation under a different project name.
`OPENAI_API_KEY` and `TTS_AUTH_TOKEN` are explicitly empty: no shared/global paid
credential is inherited. Existing Traefik routing is inherited only on a future
approved transition. No host ports are added.

The image was built successfully from the **repository root**, not `server/`:

```sh
cd /Users/tinyserve/Projects/KeineMagie
docker build --pull=false --network=none -f server/Dockerfile -t keinemagie:translator .
```

Built image ID:
`sha256:2ca874e9c80137e08fb4d275502035bbd4d890b86da016e1d2d7f9391dba474e`.
Runtime image user: `nonroot:nonroot` (65532). Build used local base images and
cached module download; build RUN steps had networking disabled. Buildx is absent;
the legacy builder succeeded. Image includes only Dockerfile's explicit web asset
allowlist. **Built successfully does not mean security-reviewed, startup-tested,
or functionally verified**. Source may change during concurrent review; rebuild
after fixes and record the new image ID before transition.

## Parent-only transition AFTER security review (NOT executed)

The live container's actual Compose base is:

`/Users/tinyserve/Library/Application Support/tinyserve/generated/.staging-20261108-144857/docker-compose.yml`

It currently includes the older scratch persistence override. The new durable
override includes those same mounts, so use base + new override, without needing
the expiring scratch file:

```sh
BASE='/Users/tinyserve/Library/Application Support/tinyserve/generated/.staging-20261108-144857/docker-compose.yml'
OVERRIDE='/Users/tinyserve/Library/Application Support/tinyserve/services/keinemagie/deployment/compose.translator.yml'

# Recheck base is still the intended configuration; review tests/security first.
# This validation ran successfully during preparation and does not start anything:
docker-compose -p tinyserve -f "$BASE" -f "$OVERRIDE" config --quiet

# STOP: only parent executes the next command after approval and backup review.
docker-compose -p tinyserve -f "$BASE" -f "$OVERRIDE" up -d --pull never --no-deps keinemagie
```

Before transition, obtain a consistent encrypted backup of existing auth/history
and provider data (including locks/host identity), retain the key separately,
and preserve the old image for rollback. Do not delete volumes or reset users.
After transition, inspect the exact target container's image/env/mounts/user,
verify HTTPS `/health` with normal certificate checks, verify unauthorized and
cross-origin mutations stay closed, and confirm existing users still work. Do not
exercise real paid/provider consent without explicit authorization. Recreating
only `keinemagie` avoids touching cloudflared and other services.

**Lifecycle caveat:** `tinyserve deploy --service keinemagie` previously failed by
unconditionally pulling a local image and may regenerate configuration without
this override. The override lives outside staging/scratch and therefore survives
file regeneration, but it is **not automatically loaded** by tinyserve. Always
include it explicitly; do not claim a supported orchestrator deployment. No
registry image was pushed/published and tinyserve's registered image remains
`keinemagie:local`. A supported registry release or local-image lifecycle support
is still required for normal unattended deploys.

## Verification artifacts and preparation helpers

Scratch files (not required for future application startup):

- `/Users/tinyserve/.hermes/cache/scratch/prepare-keinemagie-translator.py`
  — exclusive key creation, volume preparation and UID/read-only checks;
  existing keys must compare equal or it stops, never rotates them.
- `/Users/tinyserve/.hermes/cache/scratch/verify-keinemagie-preparation.py`
  — validated merged Compose JSON in memory, printing no unrelated service secrets;
  checked origin, key, explicit env, external volumes, no host ports, image user,
  and unchanged running container.
- `/Users/tinyserve/.hermes/cache/scratch/keinemagie-translator-preparation.json`
  — mode 0600, sanitized original container/auth-count record.

Verification result: merged Compose valid; external mounts correct; read-only key
verified as UID 65532; existing auth bytes unchanged; live image remains
`keinemagie:local`. New app startup/public functionality deliberately untested
until parent review. Remaining gates: security review/tests, latest-source image
rebuild if needed, secure backup/at-rest encryption decision, then parent transition.
