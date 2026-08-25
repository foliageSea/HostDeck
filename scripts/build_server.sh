#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/server"
WEB_DIR="$ROOT_DIR/host-deck-ui/dist"

echo "Building frontend..."
pnpm --dir "$ROOT_DIR/host-deck-ui" install
pnpm --dir "$ROOT_DIR/host-deck-ui" build

echo "Resolving Dart dependencies..."
flutter pub get

echo "Building Dart CLI bundle..."
rm -rf "$BUILD_DIR"
APP_VERSION="$(sed -n 's/^version:[[:space:]]*//p' "$ROOT_DIR/pubspec.yaml")"
test -n "$APP_VERSION"
dart build cli --target bin/server.dart --output "$BUILD_DIR"
printf '%s' "$APP_VERSION" > "$BUILD_DIR/bundle/VERSION"
cp "$ROOT_DIR/LICENSE" "$BUILD_DIR/bundle/LICENSE"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$BUILD_DIR/bundle/THIRD_PARTY_NOTICES.md"

echo "Copying web assets..."
rm -rf "$BUILD_DIR/bundle/web"
mkdir -p "$BUILD_DIR/bundle/web"
cp -R "$WEB_DIR"/* "$BUILD_DIR/bundle/web/"

echo "Done. Output directory: $BUILD_DIR"
