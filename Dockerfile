ARG HOSTDECK_VERSION=dev
ARG HOSTDECK_REVISION=unknown

FROM node:22-bookworm-slim AS web-builder
WORKDIR /src/host-deck-ui

COPY host-deck-ui/package.json host-deck-ui/pnpm-lock.yaml* host-deck-ui/pnpm-workspace.yaml ./
COPY host-deck-ui/packages/webos/package.json ./packages/webos/package.json
COPY host-deck-ui/examples/webos-demo/package.json ./examples/webos-demo/package.json
RUN npm install -g pnpm@10.34.5 && pnpm install --frozen-lockfile

COPY host-deck-ui/ ./
COPY LICENSE THIRD_PARTY_NOTICES.md /src/
RUN pnpm build

FROM ghcr.io/cirruslabs/flutter:stable AS server-builder
WORKDIR /src

COPY pubspec.yaml pubspec.lock ./
COPY bin ./bin
COPY lib ./lib
COPY host-deck-sidecar/pubspec.yaml ./host-deck-sidecar/pubspec.yaml
COPY host-deck-sidecar/lib ./host-deck-sidecar/lib

RUN flutter pub get
RUN dart build cli --target bin/server.dart -o build/server

FROM oven/bun:1.4.3 AS bun-runtime

FROM node:22-bookworm-slim AS ai-builder
COPY --from=bun-runtime /usr/local/bin/bun /usr/local/bin/bun
WORKDIR /src/host-deck-ai
COPY host-deck-ai/package.json host-deck-ai/pnpm-lock.yaml host-deck-ai/pnpm-workspace.yaml ./
RUN npm install -g pnpm@10.34.5 && pnpm install --frozen-lockfile
COPY host-deck-ai/ ./
RUN node build-bin.mjs dist/bridge

# The official 3.11.0 SDK tag is based on trixie; run the SDK on bookworm for these assets.
FROM --platform=$BUILDPLATFORM dart:3.11.0-sdk AS sidecar-sdk
FROM --platform=$BUILDPLATFORM node:22-bookworm-slim AS sidecar-toolchain
ENV PATH="/usr/lib/dart/bin:${PATH}"
COPY --from=sidecar-sdk /usr/lib/dart /usr/lib/dart
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY scripts/sidecar_assets.mjs ./scripts/sidecar_assets.mjs
COPY host-deck-sidecar/ ./host-deck-sidecar/

# Release CI builds and smoke-tests each sidecar on a matching native runner.
FROM sidecar-toolchain AS sidecar-native-builder
ARG TARGETARCH
ARG BUILDARCH
ARG HOSTDECK_VERSION
RUN test "$TARGETARCH" = "$BUILDARCH" \
    && node scripts/sidecar_assets.mjs build /out "$HOSTDECK_VERSION" "$TARGETARCH"
FROM scratch AS sidecar-native
COPY --from=sidecar-native-builder /out/ /

# Dart 3.11 supports Linux x64/arm64 cross-compilation for this pure Dart program.
FROM sidecar-toolchain AS sidecar-builder
ARG HOSTDECK_VERSION
RUN node scripts/sidecar_assets.mjs build /out "$HOSTDECK_VERSION" amd64 arm64 \
    && node scripts/sidecar_assets.mjs manifest /out "$HOSTDECK_VERSION"
# Release CI replaces this stage with the validated asset directory from the native matrix.
FROM scratch AS sidecar-assets
COPY --from=sidecar-builder /out/ /

FROM debian:bookworm-slim AS runtime
ARG HOSTDECK_VERSION
ARG HOSTDECK_REVISION
WORKDIR /app

LABEL org.opencontainers.image.version="${HOSTDECK_VERSION}"
LABEL org.opencontainers.image.revision="${HOSTDECK_REVISION}"
LABEL org.opencontainers.image.source="https://github.com/foliageSea/HostDeck"
LABEL org.opencontainers.image.licenses="GPL-3.0-only"
ENV HOSTDECK_VERSION="${HOSTDECK_VERSION}"
# Set HOSTDECK_ACCESS_TOTP_SECRET when starting the container to enable TOTP login.
ENV HOSTDECK_ACCESS_TOTP_SECRET=""

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        libsqlite3-0 \
        libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=server-builder /src/build/server/bundle/ ./
COPY --from=sidecar-assets --chmod=0644 /manifest.json ./sidecars/
COPY --from=sidecar-assets --chmod=0755 /hostdeck-file-sidecar-linux-amd64 /hostdeck-file-sidecar-linux-arm64 ./sidecars/
COPY --from=ai-builder /src/host-deck-ai/dist/bridge ./ai/bridge
COPY --from=web-builder /src/host-deck-ui/dist ./web
COPY LICENSE THIRD_PARTY_NOTICES.md ./

EXPOSE 8080
VOLUME ["/data"]

CMD ["/app/bin/server", "--host", "0.0.0.0", "--port", "8080", "--web-dir", "/app/web", "--data-dir", "/data"]
