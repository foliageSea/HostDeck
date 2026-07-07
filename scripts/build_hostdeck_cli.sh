#!/usr/bin/env sh
set -eu
(set -o pipefail) 2>/dev/null && set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/build/hostdeck-cli"

usage() {
  echo "Usage: $0 [--output <dir>]"
  echo "Example: $0"
  echo "Example: $0 --output build/hostdeck-cli"
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output)
      [ "$#" -ge 2 ] || fail "Missing value for --output"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

case "$OUTPUT_DIR" in
  /*) ;;
  *) OUTPUT_DIR="$ROOT_DIR/$OUTPUT_DIR" ;;
esac

if command -v fvm.bat >/dev/null 2>&1; then
  dart_tool() {
    fvm.bat dart "$@"
  }
elif command -v fvm >/dev/null 2>&1; then
  dart_tool() {
    fvm dart "$@"
  }
else
  require_command dart
  dart_tool() {
    dart "$@"
  }
fi

cd "$ROOT_DIR"

[ -f "$ROOT_DIR/bin/hostdeck_cli.dart" ] || fail "bin/hostdeck_cli.dart not found"

echo "Resolving Dart dependencies..."
dart_tool pub get

echo "Building hostdeck_cli..."
rm -rf "$OUTPUT_DIR"
dart_tool build cli --target bin/hostdeck_cli.dart --output "$OUTPUT_DIR"

echo "Done. Output directory: $OUTPUT_DIR"
