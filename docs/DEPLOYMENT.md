# Local development and tinyserve deployment

## Host findings
- Apple Silicon Mac, Swift 6.2.3 command-line toolchain present.
- Xcode was initially absent; it has since been installed: `xcodebuild -version` reports Xcode 27.2 (27B52). The actual simulator SDK build is currently blocked by an unaccepted Xcode license (exit 69). The owner must review/accept the license, open Xcode to finish setup, and install an iOS simulator runtime. If needed select its developer directory (for the usual location):
  ```sh
  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
  xcodebuild -version
  xcrun simctl list devices available
  ```
  The agent cannot claim an iOS build or simulator run until this succeeds.
- Go and XcodeGen were installed through Homebrew for this project.
- `tinyserve` CLI exists, but `tinyserve status` and `tinyserve service list` returned connection refused on `127.0.0.1:7070`. No service was deployed or exposed.

## Private local server
See `../server/README.md` for environment configuration. Store credentials in ignored `server/.env`; never paste them into Telegram or commit them.

```sh
cd server
cp .env.example .env
# Set OPENAI_API_KEY and a strong TTS_AUTH_TOKEN in your editor.
go test -race ./...
go vet ./...
go run .
```

The simulator can use a loopback server URL. An iPhone's `localhost` is the phone itself, not this Mac: use a reachable HTTPS hostname or a carefully configured private development connection.

## SwiftUI app
From `native/`, generate the Xcode project using `xcodegen generate`, then open `KeineMagie.xcodeproj`. Configure your signing team for a physical device. Enter server URL and the private server bearer token in app settings. The OpenAI provider key stays on the server. Core tests run independently using `bash native/test-core.sh` from the repository root (standalone CLT workaround); `cd native/Core && swift test` works with a complete Xcode toolchain.

## tinyserve rollout (pending)
Do not silently initialize/reconfigure an existing tinyserve installation. First resolve why its daemon is unavailable, inspect the actual service list, and choose the service name, persistent data directory and HTTPS hostname with the owner.

The repository already has a GHCR Docker workflow. It currently publishes `ghcr.io/<repository_owner>/diktat-server` on pushes to main. No image from the new working tree has been published. Confirm image architecture and exact image digest after the first release before deployment.

After publishing an image and confirming tinyserve is healthy, the CLI supports the following configuration shape (replace all placeholders, do not run verbatim):

```sh
tinyserve service add \
  --name keine-magie \
  --image ghcr.io/<owner>/diktat-server:<verified-tag> \
  --port 8787 \
  --hostname <chosen-https-hostname> \
  --env-file <absolute-private-env-path> \
  --volume <absolute-private-data-dir>:/app/data \
  --volume <absolute-private-cache-dir>:/app/cache
```

Use the actual container storage paths documented by the server. Set `HOST=0.0.0.0` within the container only; use a nonroot-writable persistent directory for history and cache. Do not publish the service before configuring authentication. DNS/Cloudflare changes require the selected hostname and an explicit decision; `--cloudflare` and `--deploy` are not included above intentionally.

Verify after deployment:
- Exact service shows the intended image, hostname, volumes and health.
- `GET /health` works over HTTPS.
- Unauthenticated translation/TTS requests are denied.
- An authorized translation completes using the real provider (incurs a charge).
- History survives service restart, without exposing its file publicly.
- TTS plays from the iPhone; repeated requests use cache.
- Rate/cost controls, backup policy and data deletion are decided before broader access.

## Secrets and cost
API billing is separate from a ChatGPT subscription, but eligible Pro/Business plans can activate subscription-linked promotional API credits. Check the benefit in ChatGPT Settings → Billing and confirm its grant in the linked API organization before buying additional credits. Plus is not included in this API-credit benefit. An active promotional grant does not require an API payment method. See https://help.openai.com/en/articles/20001626-api-credits-benefit-for-eligible-chatgpt-subscriptions . Provision a project API key, inspect provider usage, and select an application budget. Never reuse the Hermes runtime credential just because it is available on the host. Live paid requests require intentionally configured project credentials; simulated upstreams belong only in tests.
