# Fixed 30-day browser sessions

## Policy and verification

User-approved change: **new** Apple web sign-ins and native-approved browser pairings receive a fixed **30 × 24 hour** session. `browserSessionLifetime` supplies both cookie Max-Age and durable absolute expiry. There is no rolling refresh, migration, session reset or expired-session resurrection. Existing 24-hour sessions keep their deadlines until a new login. Native 30-day policy, transaction/bootstrap five-minute cookies, CSRF, Secure/HttpOnly/SameSite and logout semantics are unchanged.

Both issuance paths were tested RED against the previous 24-hour implementation: actual cookie Max-Age 86400, expiry at 24h, 401 at 24h/just-after/just-before-30d and failed logout at 25h. Each then passed GREEN after its narrowly scoped implementation change.

Regression coverage exercises signed synthetic Apple callback and full pairing start/inspect/approve/poll; exact 30-day expiry; no Set-Cookie or store-byte changes on session GET/reopen; logout at 25h, cross-origin/missing-CSRF denial and durable revocation after reload. Legacy records retain original deadlines; fresh login cannot resurrect expired records or alter native sessions. The existing provider contract's expired-session fixture now starts 31 days ago rather than 48 hours ago.

Full `go test ./... -count=1`, `go test -race ./... -count=1`, `go vet ./...` and `git diff --check` passed. Separate self-review of the production diff found only one duration constant and four uses; lookup/revoke/native/OAuth transaction behavior is untouched. No production identity, cookie or provider calls used. Parent independent verification remains a separate acceptance gate; no independent-agent review is claimed here.

## Release

Release provenance and preservation evidence will be recorded after deployment. Backend-only source paths do not trigger the native TestFlight workflow. The existing explicit Compose lifecycle and local Apple Silicon build are retained; CI registry publication is separate from the running local artifact.
