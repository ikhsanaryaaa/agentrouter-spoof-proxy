# syntax=docker/dockerfile:1
# Go build, multi-stage with native cross-compile via TARGETOS and TARGETARCH
# (no QEMU). Final image is 15 to 25 MB. HEALTHCHECK uses binary -healthcheck
# flag because distroless has no shell or wget.
FROM --platform=$BUILDPLATFORM golang:1.26 AS build
ARG TARGETOS TARGETARCH
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd/ cmd/
COPY internal/ internal/
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags="-s -w" -o /out/proxy ./cmd/proxy

FROM gcr.io/distroless/static-debian13:nonroot
COPY --from=build /out/proxy /proxy
EXPOSE 8318
# Exec-form healthchecks run as the bare argv with no ENTRYPOINT prefix, so
# this must name the binary explicitly. CMD ["-healthcheck"] made the runtime
# look for a program literally called "-healthcheck", which exited 127 every
# time and left every container "unhealthy" despite a working server.
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/proxy", "-healthcheck"]
ENTRYPOINT ["/proxy"]
