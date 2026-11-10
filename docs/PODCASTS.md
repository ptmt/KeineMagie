# Podcast preparation and public source discovery

## Delivered contract

Authenticated native-session routes (no shared `TTS_AUTH_TOKEN` fallback):

- `GET /v1/podcasts`: owner's items, `worker_available`, source/size/time limits.
- `POST /v1/podcasts`: `{ "url": "https://public.example/episode.mp3", "source_language": "de" }`, returns 202 and a durable job. `ru` is also accepted; translations are DE↔RU.
- `GET /v1/podcasts/{id}`: owner-only state and aligned timestamped segments.
- `POST /v1/podcasts/{id}/cancel`, `POST .../retry`; `DELETE .../{id}` for nonactive jobs.
- `POST /v1/podcasts/discover`: `{ "url": "https://public.example/show" }` returns RSS/Atom metadata without processing audio.
- `GET /v1/podcasts/subscriptions`, `POST .../subscriptions` with the same URL body: persistent owner-only subscriptions and initial episode discovery.
- `POST /v1/podcasts/subscriptions/{id}/refresh`; `DELETE .../subscriptions/{id}`. Refresh is explicitly manual, not background scheduling. Discovery/subscription/refresh require no connected AI provider and work when recognition is unavailable.

Feed subscription never enqueues transcription or translation. The native library lists discovered titles/dates and each episode has its own explicit Prepare button, using the existing ingestion and personal translation budgets. Browser cookie requests require exact configured Origin and session-bound CSRF for every mutation (including network discovery); native requests require the existing bearer session.

States: queued → fetching → transcribing → translating → completed, or failed/canceled. Segments contain `start`, `end`, real recognized `text`, and completed `translation`. Progress is stage/segment progress, not a claim about Whisper's internal percent. Partial translations remain visible on failure; retry currently reprocesses the entire source and consumes quotas again. No playback, recording, shadowing scoring or enrichment is claimed in this slice.

Storage is `podcasts/jobs.json` beside `HISTORY_PATH`, with owner-only files, cross-process flock, temp-write/fsync/rename/directory-fsync. Claims are fenced; canceled/recovered workers cannot publish. One cross-process worker holds an OS lock. A crashed in-flight claim becomes reclaimable after 45 minutes; each job has at most 3 starts. A processing attempt is limited to 40 minutes; fetch to 2 minutes; DNS/connect and headers have separate bounds. Temporary audio is deleted after an attempt; an abrupt process/host crash can leave an owner-only `audio-*` scratch directory requiring administrator cleanup while the server is stopped.

Budgets: 40 MiB downloaded, 10 minutes decoded audio, 20 MiB normalized WAV, 120 segments, 8,000 transcript characters; 2 active and 30 retained items per owner, 4 admitted create/retry attempts per owner per UTC day, 32 active jobs and 500 retained jobs globally. Per-segment translation also uses the existing durable personal translation quota (default 100 attempts/day) and owner serialization. An episode can exhaust the daily translation quota and fail; there is no automatic paid/shared-key fallback. Cancellation is observed within about a second plus process termination/network cancellation.

## Source and SSRF boundary

Supported: public direct audio (validated response media type, no filename suffix required), static HTML episode pages with `<audio src>`, `<audio><source src>`, or `og:audio` metadata, and RSS/Atom audio enclosures. Relative references resolve against the final response URL. Subscription accepts a public feed or follows one HTML `<link rel="alternate" type="application/rss+xml|application/atom+xml">` link. Apple/Spotify pages work only if they actually expose such a public feed link or static audio; no endpoint is guessed. JavaScript players, DRM, login walls, YouTube, signed/query URLs, userinfo, fragments and nonstandard ports are unsupported. A page without extractable audio returns an explicit error, not a fabricated transcript.

All page/feed/audio requests use the same hardened transport. Each redirect is validated (at most 3 redirects per request); every connection resolves all DNS answers, denies any private/special-use answer, and dials the validated IP directly. Environment proxies are disabled. No browser cookies, Authorization headers or server/provider credentials are attached. HTML/feed documents are bounded to 2 MiB; XML depth 32 and 200,000 tokens; DTD/directives are rejected and external entities are never followed. Discovery has a 30-second total deadline. HTML audio resolution plus download has a 2-minute total deadline. The selected static audio URL is fetched directly, not recursively extracted. Decoder tools receive only local downloaded files.

Subscriptions are stored in the existing durable jobs store, capped at 10 per owner and 100 globally, with 50 retained episodes each. Refresh merges recent feed order with prior metadata, deduplicating both GUID/Atom ID and enclosure URL. The first 50 feed entries are treated as the publisher's latest-first order; no historical backfill is attempted. Metadata strings are capped at 4 KiB. Discovery and manual refresh share a 6-per-minute owner limit. Unsubscribe fences an already in-flight refresh so it cannot recreate the deleted subscription. There is no scheduled feed worker in this slice, and foreground progress polling only reads stored metadata.

The Mac has ffmpeg 8.1.1, yt-dlp 2026.06.09, Whisper CLI, and cached `base.pt` / `small.pt`; Docker is Linux arm64. The yt-dlp spike successfully resolved YouTube `jNQXAC9IVRw` (19 seconds), while its historical test video was unavailable. This is not a safe general extraction implementation: yt-dlp independently follows extraction/media URLs outside the hardened Go transport. YouTube remains explicitly rejected until that entire network graph has equivalent SSRF and resource controls. Installing yt-dlp alone is not sufficient.

## Transcription modality and runtime

Official [ChatGPT-plan models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference.md), checked 2026-11-10, documents account model discovery and public Responses text inference with `store=false`, `stream=true`. It does **not** establish personal-plan authorization to `/audio/transcriptions`. No such endpoint is invoked or assumed. Recognition is local OpenAI Whisper (`base`, CPU, 2 threads); translations reuse this owner's existing personal provider catalog, token refresh, prompts and strict completed Responses handling.

The distroless backend intentionally contains **no Python/Whisper/ffmpeg**. Recognition now uses a dedicated authenticated Linux worker; the existing backend remains the sole identity/provider authority and durable job writer. Do **not** migrate the backend onto the Mac or mount Homebrew binaries into Linux. Production local-executable configuration is disabled.

See [isolated worker build, verified fixture and deployment handoff](../server/podcast-worker/README.md). Configure only `PODCAST_WORKER_URL` and `PODCAST_WORKER_TOKEN_FILE` on the existing backend after an approved candidate rollout, retaining all existing mounts. The worker shares only an internal Docker network, no public ports/routing, and a dedicated 0600 token file; it receives bounded audio bytes, never URLs or provider credentials. Missing/unready worker fails new ingestion closed while the library remains usable. Translation continues through this owner's provider in the backend. No production deployment is claimed.

## Native app and share signing gate

`PodcastLibraryView` imports URLs explicitly, polls progress, shows original/aligned translations, and supports cancel/retry/delete. `PodcastAPI` is separate from the existing text APIClient. The share extension writes **only an untrusted URL** to a protected App Group inbox. It has no session/provider credentials and never submits work. The signed-in main app shows “Shared URLs — confirm before sending”; the user's final import chooses language and authenticates with the app's existing private Keychain token. No keychain-sharing entitlement or responder-chain app-open hack is used.

The normal `project.yml` remains app-only and continues using the existing distribution profile. The extension must **not** be activated for TestFlight with today's app-only signing inputs. Opt-in project generation:

```sh
cd native
xcodegen generate --spec project-share.yml
# To return to existing app-only CI setup:
xcodegen generate --spec project.yml
```

Before shipping the opt-in project, register/enable with Apple team **49PJNAT2WC**:

1. Existing main App ID **de.keinemagie.app**: retain Sign in with Apple and add App Groups.
2. New extension App ID **de.keinemagie.app.share**: App Groups.
3. App Group **group.de.keinemagie.app**, assigned to both IDs.
4. Regenerate the main App Store distribution profile with the group; create a separate extension App Store distribution profile using the matching distribution certificate.
5. Extend protected CI to install/validate both profiles and export mappings. Existing `BUILD_PROVISION_PROFILE_BASE64` is app-only; a new proposed `BUILD_SHARE_PROVISION_PROFILE_BASE64` must be wired into CI rather than just added as an unused secret. The overlay provides `KM_CI_SHARE_PROVISIONING_PROFILE` and `KM_CI_SHARE_PROVISIONING_PROFILE_SPECIFIER` settings, but the current signing script does not yet supply them.
6. Validate a real signed archive and device share-sheet round trip before activation. Simulator compile is not a provisioning or device-sharing test.

Without those entitlements the app's manual URL import still works; inbox unavailable is not reported as successful saving.

## Verified gates

- All Go tests and race tests pass.
- `PODCAST_REAL_TEST=1 go test -race ./... -run TestPodcast -v -count=1`: real `say` German speech → ffprobe/ffmpeg → installed Whisper recognized “Guten Morgen, heute lernen wir zusammen Deutsch, das Wetter ist schön.” A fixture HTTP transport then exercised durable queued/fetching/transcribing/translating/completed with real recognition and synthetic personal Responses wire events: completed, 1 aligned segment, progress 100. Only the provider response is synthetic; this is not a real-account translation claim.
- Swift package tests pass (44 Swift Testing tests plus 2 podcast XCTest tests at verification time).
- Both standard and share-overlay iOS Simulator builds succeed, including the embedded extension for the overlay.
- No production deployment, Apple identifier/profile changes, TestFlight upload, real-account translation, or physical-device share delivery was performed.
