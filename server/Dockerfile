# syntax=docker/dockerfile:1
FROM golang:1.22-bookworm AS build

WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o /out/server ./

FROM gcr.io/distroless/base-debian12:nonroot
WORKDIR /app
COPY --from=build /out/server /app/server
EXPOSE 8787
USER nonroot:nonroot
ENTRYPOINT ["/app/server"]
