#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/server"
WEB_DIR="$ROOT_DIR/host-deck-ui/dist"

cd "$ROOT_DIR"

echo "Building frontend..."
pnpm --dir "$ROOT_DIR/host-deck-ui" install --frozen-lockfile
pnpm --dir "$ROOT_DIR/host-deck-ui" build

echo "Resolving Dart dependencies..."
dart pub get

echo "Building Dart CLI bundle..."
APP_VERSION="$(sed -n 's/^version:[[:space:]]*\([^[:space:]#][^[:space:]#]*\).*$/\1/p' "$ROOT_DIR/pubspec.yaml")"
if [[ -z "$APP_VERSION" ]]; then
  printf 'Unable to resolve the application version from %s\n' "$ROOT_DIR/pubspec.yaml" >&2
  exit 1
fi
rm -rf "$BUILD_DIR"
dart build cli --target bin/server.dart --output "$BUILD_DIR"
node "$ROOT_DIR/scripts/sidecar_assets.mjs" stage "$BUILD_DIR/bundle"
node "$ROOT_DIR/scripts/build_ai.mjs" "$BUILD_DIR/bundle"
printf '%s' "$APP_VERSION" > "$BUILD_DIR/bundle/VERSION"
cp "$ROOT_DIR/LICENSE" "$BUILD_DIR/bundle/LICENSE"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$BUILD_DIR/bundle/THIRD_PARTY_NOTICES.md"

echo "Copying web assets..."
rm -rf "$BUILD_DIR/bundle/web"
mkdir -p "$BUILD_DIR/bundle/web"
cp -R "$WEB_DIR"/* "$BUILD_DIR/bundle/web/"

echo "Done. Output directory: $BUILD_DIR"
