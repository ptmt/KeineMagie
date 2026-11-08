# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM golang:1.22-bookworm AS build
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . ./
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-$(go env GOARCH)} go build -trimpath -ldflags="-s -w" -o /out/server ./
RUN mkdir -p /out/data /out/cache && chmod 700 /out/data /out/cache

FROM gcr.io/distroless/base-debian12:nonroot
WORKDIR /app
COPY --from=build /out/server /app/server
COPY --from=build --chown=65532:65532 /out/data /app/data
COPY --from=build --chown=65532:65532 /out/cache /app/cache
ENV HOST=0.0.0.0 PORT=8787 HISTORY_PATH=/app/data/history.json TTS_CACHE_DIR=/app/cache
EXPOSE 8787
USER nonroot:nonroot
ENTRYPOINT ["/app/server"]
