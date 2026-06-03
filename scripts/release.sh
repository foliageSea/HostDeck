#!/usr/bin/env sh
set -eu
(set -o pipefail) 2>/dev/null && set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UI_DIR="$ROOT_DIR/host-deck-ui"
PUBSPEC_PATH="$ROOT_DIR/pubspec.yaml"
PACKAGE_JSON_PATH="$UI_DIR/package.json"
REMOTE="${RELEASE_REMOTE:-origin}"

usage() {
  echo "Usage: $0 [version]"
  echo "Example: $0 1.0.1"
  echo "Example: $0 1.0.1+2"
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

if [ "${1:-}" = "--" ]; then
  shift
fi

VERSION="${1:-}"

if [ "$VERSION" = "-h" ] || [ "$VERSION" = "--help" ]; then
  usage
  exit 0
fi

if [ -z "$VERSION" ]; then
  printf 'Release version: '
  read -r VERSION
fi

VERSION="$(printf '%s' "$VERSION" | tr -d '[:space:]')"

if [ -z "$VERSION" ]; then
  fail "version is required"
fi

if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'; then
  fail "version must be semver, for example 1.0.1 or 1.0.1+2"
fi

TAG_VERSION="${VERSION%%+*}"
TAG="v$TAG_VERSION"

require_command git
require_command gh
require_command node
require_command pnpm

cd "$ROOT_DIR"

[ -f "$PUBSPEC_PATH" ] || fail "pubspec.yaml not found"
[ -f "$PACKAGE_JSON_PATH" ] || fail "host-deck-ui/package.json not found"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not inside a git repository"

if [ -n "$(git status --porcelain)" ]; then
  fail "working tree is not clean; commit or stash existing changes first"
fi

git fetch "$REMOTE" --tags

if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
  fail "tag already exists locally: $TAG"
fi

if git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$TAG" >/dev/null 2>&1; then
  fail "tag already exists on $REMOTE: $TAG"
fi

echo "Updating pubspec.yaml to $VERSION..."
node -e '
const fs = require("node:fs")
const file = process.argv[1]
const version = process.argv[2]
const text = fs.readFileSync(file, "utf8")
if (!/^version:\s*[^\s#]+\s*(?:#.*)?$/m.test(text)) {
  throw new Error(`No version field found in ${file}`)
}
fs.writeFileSync(file, text.replace(/^version:\s*[^\s#]+(\s*(?:#.*)?)$/m, `version: ${version}$1`))
' "$PUBSPEC_PATH" "$VERSION"

echo "Syncing frontend package version..."
pnpm --dir "$UI_DIR" sync:version

echo "Refreshing pnpm lockfile..."
pnpm --dir "$UI_DIR" install --lockfile-only

if [ -z "$(git status --porcelain)" ]; then
  fail "no version changes detected"
fi

echo "Changed files:"
git status --short

git add pubspec.yaml host-deck-ui/package.json host-deck-ui/pnpm-lock.yaml

git commit -m "chore(release): 发布 $TAG"
git tag -a "$TAG" -m "Release $TAG"

echo "Pushing commit and tag to $REMOTE..."
git push "$REMOTE" HEAD
git push "$REMOTE" "$TAG"

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "GitHub release already exists: $TAG"
else
  echo "Creating GitHub release: $TAG..."
  gh release create "$TAG" --title "HostDeck $TAG" --generate-notes
fi

echo "Release started: $TAG"
echo "GitHub Actions will build and upload release assets."
