ARG HOSTDECK_VERSION=dev
ARG HOSTDECK_REVISION=unknown

FROM node:20-bookworm-slim AS web-builder
WORKDIR /src/host-deck-ui

COPY host-deck-ui/package.json host-deck-ui/pnpm-lock.yaml* ./
RUN npm install -g pnpm && pnpm install

COPY host-deck-ui/ ./
RUN pnpm build

FROM ghcr.io/cirruslabs/flutter:stable AS server-builder
WORKDIR /src

COPY pubspec.yaml pubspec.lock ./
COPY bin ./bin
COPY lib ./lib

RUN flutter pub get
RUN dart build cli --target bin/server.dart -o build/server

FROM debian:bookworm-slim AS runtime
ARG HOSTDECK_VERSION
ARG HOSTDECK_REVISION
WORKDIR /app

LABEL org.opencontainers.image.version="${HOSTDECK_VERSION}"
LABEL org.opencontainers.image.revision="${HOSTDECK_REVISION}"
LABEL org.opencontainers.image.source="https://github.com/foliageSea/HostDeck"
LABEL org.opencontainers.image.licenses="GPL-3.0-only"
ENV HOSTDECK_VERSION="${HOSTDECK_VERSION}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        libsqlite3-0 \
        libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=server-builder /src/build/server/bundle/ ./
COPY --from=web-builder /src/host-deck-ui/dist ./web
COPY LICENSE THIRD_PARTY_NOTICES.md ./

EXPOSE 8080
VOLUME ["/data"]

CMD ["/app/bin/server", "--host", "0.0.0.0", "--port", "8080", "--web-dir", "/app/web", "--data-dir", "/data"]
