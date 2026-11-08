# Architecture

## Boundaries
- `native/`: SwiftUI app, with Foundation-based core package independently testable using SwiftPM.
- `server/`: Go HTTP service; provider credentials stay here. Keep existing `/health` and `/tts` compatibility.
- The legacy Expo client has been removed from the working tree; Git history retains it. SwiftUI is the only active client.
- `docs/`: specification, architecture, delivery status, deployment instructions.

## Initial data flow
SwiftUI → authenticated Go API → OpenAI API. Translation result includes idioms, patterns and vocabulary; successful results persist server-side and can be fetched as history. OpenAI annotations should be presented as suggestions, not verified grammar facts.

The initial shared bearer token is suitable ONLY for a private single-user deployment. It is not a multi-tenant auth design. The app stores it in Keychain, not source control or UserDefaults. Never embed an OpenAI secret in a shipped app. A commercial app requires user identities, per-user history, scoped sessions, abuse prevention and enforceable budgets.

## API contract (initial)
`Authorization: Bearer <TTS_AUTH_TOKEN>` on translation/history and TTS requests. `GET /health` is public and does not prove provider credentials work.

`POST /v1/translations`:
```json
{"text":"Das ist nicht mein Bier.","source_language":"de","target_language":"ru"}
```

Successful response shape (schema illustration, not a recorded live translation):
```text
id: string
created_at: RFC3339 timestamp
text: string
source_language: de | ru
target_language: ru | de
translation: string
idioms: [{expression, meaning, example}]
patterns: [{pattern, explanation}]
vocabulary: [{word, meaning}]
```
`GET /v1/translations` returns `{ "items": [...] }`, newest first. This is a private single-user history; pagination, retention and user isolation are future work.

`POST /tts`: existing audio endpoint. Text, voice/model/format/speed settings; returns audio bytes with cache headers. OpenAI speech synthesis first. See `server/README.md` for the implemented details.

## Storage
Local persistent history and TTS cache under configurable paths, mounted as persistent volumes when containerized. The first release does not provide device synchronization accounts, analytics tables, podcast job storage or a vector database. Future event storage should model translations, dictation attempts, episode segments and review interactions with stable IDs and source provenance.

## Security and production gates
- Default bind loopback; explicitly bind `0.0.0.0` inside an isolated container, not casually on the host.
- TLS via a correctly configured reverse proxy/tinyserve hostname for physical devices.
- No arbitrary source URLs or user-controlled provider URLs from mobile requests.
- Configure secrets outside the repository; do not paste secrets into Telegram or log request bodies.
- Imported text/audio leaves the machine for OpenAI processing. Explain this before upload.
- No public deployment until auth, rate limits, cost limits, deletion/retention and backup/restore have been reviewed.
- Existing TTS behavior is legacy and still needs a broader concurrency/cache/security review before multi-user use.

## Verification boundaries
Unit and local HTTP tests can run without a provider key using an explicitly simulated upstream in test code. They do not establish live model accuracy, voice quality, provider quota, iOS rendering, device networking or APNs delivery. Record actual checks separately from planned ones.
