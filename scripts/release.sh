#!/usr/bin/env sh
set -eu
(set -o pipefail) 2>/dev/null && set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UI_DIR="$ROOT_DIR/host-deck-ui"
PUBSPEC_PATH="$ROOT_DIR/pubspec.yaml"
PACKAGE_JSON_PATH="$UI_DIR/package.json"
REMOTE="${RELEASE_REMOTE:-origin}"
VERSION_ARG_PROVIDED=0

usage() {
  echo "Usage: $0 [version]"
  echo "Example: $0 1.0.1"
  echo "Example: $0 1.0.1+2"
  echo "Environment: RELEASE_REMOTE=origin"
}

fail() {
  echo "错误：$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少命令：$1"
}

confirm() {
  message="$1"
  printf '%s [y/N] ' "$message"
  read -r answer
  case "$answer" in
    y | Y | yes | YES) return 0 ;;
    *) return 1 ;;
  esac
}

trim_version() {
  printf '%s' "$1" | tr -d '[:space:]'
}

normalize_version() {
  version="$(trim_version "$1")"
  printf '%s' "${version#v}"
}

is_semver() {
  printf '%s' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
}

tag_for_version() {
  version="$1"
  printf 'v%s' "${version%%+*}"
}

current_pubspec_version() {
  node -e '
const fs = require("node:fs")
const file = process.argv[1]
const text = fs.readFileSync(file, "utf8")
const match = text.match(/^version:\s*([^\s#]+)\s*(?:#.*)?$/m)
if (!match) {
  throw new Error(`No version field found in ${file}`)
}
process.stdout.write(match[1])
' "$PUBSPEC_PATH"
}

check_version_available() {
  version="$1"
  current_version="$2"
  tag="$(tag_for_version "$version")"

  if ! is_semver "$version"; then
    echo "版本号格式不正确，请使用 SemVer，例如 1.0.1、1.0.1-beta.1 或 1.0.1+2"
    return 1
  fi

  if [ "$version" = "$current_version" ]; then
    echo "新版本号不能和当前版本相同：$current_version"
    return 1
  fi

  if git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
    echo "本地 tag 已存在：$tag"
    return 1
  fi

  if git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$tag" >/dev/null 2>&1; then
    echo "远端 tag 已存在：$tag"
    return 1
  fi

  if gh release view "$tag" >/dev/null 2>&1; then
    echo "GitHub Release 已存在：$tag"
    return 1
  fi

  return 0
}

if [ "${1:-}" = "--" ]; then
  shift
fi

VERSION="${1:-}"
if [ -n "$VERSION" ]; then
  VERSION_ARG_PROVIDED=1
fi

if [ "$VERSION" = "-h" ] || [ "$VERSION" = "--help" ]; then
  usage
  exit 0
fi

require_command git
require_command gh
require_command node
require_command pnpm

cd "$ROOT_DIR"

[ -f "$PUBSPEC_PATH" ] || fail "pubspec.yaml not found"
[ -f "$PACKAGE_JSON_PATH" ] || fail "host-deck-ui/package.json not found"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not inside a git repository"
CURRENT_BRANCH="$(git branch --show-current)"
[ -n "$CURRENT_BRANCH" ] || fail "当前处于 detached HEAD，无法发版"
git remote get-url "$REMOTE" >/dev/null 2>&1 || fail "找不到 Git remote：$REMOTE"
gh auth status >/dev/null 2>&1 || fail "GitHub CLI 未登录，请先执行：gh auth login"

if [ -n "$(git status --porcelain)" ]; then
  fail "working tree is not clean; commit or stash existing changes first"
fi

echo "正在同步远端 tag..."
git fetch --tags "$REMOTE"

CURRENT_VERSION="$(current_pubspec_version)"
echo "当前版本：$CURRENT_VERSION"

if [ "$VERSION_ARG_PROVIDED" -eq 1 ]; then
  VERSION="$(normalize_version "$VERSION")"
  [ -n "$VERSION" ] || fail "version is required"
  check_version_available "$VERSION" "$CURRENT_VERSION" || fail "version is not available: $VERSION"
else
  VERSION=""
  while [ -z "$VERSION" ]; do
    printf '请输入新版本号（例如 1.0.1 或 1.0.1+2）：'
    read -r INPUT_VERSION
    INPUT_VERSION="$(normalize_version "$INPUT_VERSION")"
    if [ -z "$INPUT_VERSION" ]; then
      echo "版本号不能为空"
      continue
    fi
    if check_version_available "$INPUT_VERSION" "$CURRENT_VERSION"; then
      VERSION="$INPUT_VERSION"
    fi
  done
fi

TAG="$(tag_for_version "$VERSION")"

echo
echo "即将执行发版："
echo "  分支：$CURRENT_BRANCH"
echo "  版本：$CURRENT_VERSION -> $VERSION"
echo "  Tag：$TAG"
echo "  Remote：$REMOTE"
echo
echo "注意：GitHub Actions 通过 push.tags 触发发版构建，创建 Release 不会再次触发构建。"
confirm "确认继续？" || fail "已取消"

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

echo "Running frontend build..."
pnpm --dir "$UI_DIR" build

if [ -z "$(git status --porcelain)" ]; then
  fail "no version changes detected"
fi

echo "Changed files:"
git status --short

git add pubspec.yaml host-deck-ui/package.json host-deck-ui/pnpm-lock.yaml

git commit -m "chore(release): 发布 $TAG"
git tag -a "$TAG" -m "Release $TAG"

echo "Pushing commit and tag to $REMOTE..."
git push "$REMOTE" "$CURRENT_BRANCH"
git push "$REMOTE" "$TAG"

echo "Creating GitHub release: $TAG..."
gh release create "$TAG" --title "$TAG" --generate-notes --verify-tag

echo "Release started: $TAG"
echo "GitHub Actions will build and upload release assets."
