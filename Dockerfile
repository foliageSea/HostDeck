FROM node:20-bookworm-slim AS web-builder
WORKDIR /src/ssh-tool-ui

COPY ssh-tool-ui/package.json ssh-tool-ui/pnpm-lock.yaml* ./
RUN npm install -g pnpm && pnpm install

COPY ssh-tool-ui/ ./
RUN pnpm build

FROM ghcr.io/cirruslabs/flutter:stable AS server-builder
WORKDIR /src

COPY pubspec.yaml pubspec.lock ./
COPY bin ./bin
COPY lib ./lib

RUN flutter pub get
RUN dart build cli --target bin/server.dart -o build/server

FROM debian:bookworm-slim AS runtime
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        libsqlite3-0 \
        libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=server-builder /src/build/server/bundle/ ./
COPY --from=web-builder /src/ssh-tool-ui/dist ./web

EXPOSE 8080
VOLUME ["/data"]

CMD ["/app/bin/server", "--host", "0.0.0.0", "--port", "8080", "--web-dir", "/app/web", "--data-dir", "/data"]
