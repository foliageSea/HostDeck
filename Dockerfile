ARG HOSTDECK_VERSION=dev
ARG HOSTDECK_REVISION=unknown

FROM node:20-bookworm-slim AS web-builder
WORKDIR /src/host-deck-ui

COPY host-deck-ui/package.json host-deck-ui/pnpm-lock.yaml* host-deck-ui/pnpm-workspace.yaml ./
RUN npm install -g pnpm@10.34.5 && pnpm install

COPY host-deck-ui/ ./
COPY LICENSE THIRD_PARTY_NOTICES.md /src/
RUN pnpm build

FROM ghcr.io/cirruslabs/flutter:stable AS server-builder
WORKDIR /src

COPY pubspec.yaml pubspec.lock ./
COPY bin ./bin
COPY lib ./lib

RUN flutter pub get
RUN dart build cli --target bin/server.dart -o build/server

FROM node:22-bookworm-slim AS ai-builder
WORKDIR /src/host-deck-ai
COPY host-deck-ai/package.json host-deck-ai/package-lock.json ./
RUN npm ci
COPY host-deck-ai/ ./
RUN npm run build

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
COPY --from=ai-builder /usr/local/bin/node ./ai/node
COPY --from=ai-builder /src/host-deck-ai/dist/bridge.mjs ./ai/bridge.mjs
COPY --from=ai-builder /src/host-deck-ai/node_modules ./ai/node_modules
COPY --from=web-builder /src/host-deck-ui/dist ./web
COPY LICENSE THIRD_PARTY_NOTICES.md ./

EXPOSE 8080
VOLUME ["/data"]

CMD ["/app/bin/server", "--host", "0.0.0.0", "--port", "8080", "--web-dir", "/app/web", "--data-dir", "/data"]
