#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/server"
WEB_DIR="$ROOT_DIR/ssh-tool-ui-next/dist"

echo "Building frontend..."
pnpm --dir "$ROOT_DIR/ssh-tool-ui-next" install
pnpm --dir "$ROOT_DIR/ssh-tool-ui-next" build

echo "Resolving Dart dependencies..."
flutter pub get

echo "Building Dart CLI bundle..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
dart build cli --target "$ROOT_DIR/bin/server.dart" -o "$BUILD_DIR"

echo "Copying web assets..."
rm -rf "$BUILD_DIR/bundle/web"
mkdir -p "$BUILD_DIR/bundle/web"
cp -R "$WEB_DIR"/* "$BUILD_DIR/bundle/web/"

echo "Done. Output directory: $BUILD_DIR"
