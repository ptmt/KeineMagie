# syntax=docker/dockerfile:1
# Official current patch builder tag verified before this release.
FROM golang:1.27.4-bookworm AS build
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-$(go env GOARCH)} go build -trimpath -ldflags="-s -w" -o /out/server ./
RUN mkdir -p /out/data /out/cache && chmod 700 /out/data /out/cache

FROM gcr.io/distroless/base-debian12:nonroot
WORKDIR /app
COPY --from=build /out/server /app/server
COPY web/bootstrap.js web/index.html web/app.mjs web/core.mjs web/i18n.mjs web/episode.mjs web/episode-view.mjs web/episode-i18n.mjs web/episode.css web/styles.css web/favicon.svg web/apple-sign-in-de.png web/apple-sign-in-en.png web/apple-sign-in-ru.png web/apple-sign-in-es.png web/apple-sign-in-fr.png /app/web/
ENV WEB_ASSET_DIR=/app/web
COPY --from=build --chown=65532:65532 /out/data /app/data
COPY --from=build --chown=65532:65532 /out/cache /app/cache
ENV HOST=0.0.0.0 PORT=8787 HISTORY_PATH=/app/data/history.json TTS_CACHE_DIR=/app/cache
EXPOSE 8787
USER nonroot:nonroot
ENTRYPOINT ["/app/server"]
