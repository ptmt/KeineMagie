# Diktat TTS Server

Minimal Go server that proxies OpenAI Text-to-Speech and caches audio by input + voice + settings.

## Setup

```bash
cd server
cp .env.example .env
# edit .env to add OPENAI_API_KEY
```

## Run

```bash
go run .
```

Server runs on `http://localhost:8787` by default.

## Endpoints

- `GET /health`
- `POST /tts`

### POST /tts

Request body:

```json
{
  "text": "Hallo!",
  "voice": "alloy",
  "model": "gpt-4o-mini-tts",
  "speed": 1.0,
  "format": "mp3",
  "instructions": "Read clearly and warmly.",
  "language": "de-DE"
}
```

Response: audio bytes with `Content-Type` set to the selected format.

Headers:
- `X-Cache: HIT|MISS`
- `X-Cache-Key: <sha256>`

## Notes

- `instructions` are only forwarded when using `gpt-4o-mini-tts`.
- Cache lives in `server/cache` by default.

## Docker

```bash
docker build -t diktat-server ./server
docker run --rm -p 8787:8787 --env OPENAI_API_KEY=your_key_here diktat-server
```
