#!/usr/bin/env bash

set -euo pipefail

backend_host="127.0.0.1"
backend_port=8080
frontend_port=5178
startup_timeout_seconds=30
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
backend_pid=""
frontend_pid=""

usage() {
  cat <<'EOF'
Usage: ./dev.sh [options]

Options:
  --backend-host HOST                Backend host (default: 127.0.0.1)
  --backend-port PORT                Backend port, 1-65535 (default: 8080)
  --startup-timeout-seconds SECONDS  Startup timeout, 1-300 (default: 30)
  -h, --help                         Show this help message
EOF
}

is_integer_in_range() {
  local value="$1"
  local minimum="$2"
  local maximum="$3"

  [[ "$value" =~ ^[0-9]+$ ]] && ((value >= minimum && value <= maximum))
}

while (($#)); do
  case "$1" in
    --backend-host)
      backend_host="${2:?Missing value for --backend-host}"
      shift 2
      ;;
    --backend-port)
      backend_port="${2:?Missing value for --backend-port}"
      shift 2
      ;;
    --startup-timeout-seconds)
      startup_timeout_seconds="${2:?Missing value for --startup-timeout-seconds}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! is_integer_in_range "$backend_port" 1 65535; then
  printf '%s\n' '--backend-port must be between 1 and 65535.' >&2
  exit 1
fi

if ! is_integer_in_range "$startup_timeout_seconds" 1 300; then
  printf '%s\n' '--startup-timeout-seconds must be between 1 and 300.' >&2
  exit 1
fi

test_tcp_port() {
  nc -z -w 1 "$backend_host" "$backend_port" >/dev/null 2>&1
}

stop_process_tree() {
  local pid="$1"
  local child_pid

  [[ -n "$pid" ]] || return
  kill -0 "$pid" >/dev/null 2>&1 || return

  while IFS= read -r child_pid; do
    stop_process_tree "$child_pid"
  done < <(pgrep -P "$pid" 2>/dev/null || true)

  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" 2>/dev/null || true
}

wait_backend() {
  local deadline=$((SECONDS + startup_timeout_seconds))

  while ((SECONDS < deadline)); do
    if ! kill -0 "$backend_pid" >/dev/null 2>&1; then
      wait "$backend_pid" || true
      printf 'Backend exited during startup.\n' >&2
      return 1
    fi

    if test_tcp_port; then
      return 0
    fi

    sleep 0.2
  done

  printf 'Backend did not listen on %s:%s within %s seconds.\n' \
    "$backend_host" "$backend_port" "$startup_timeout_seconds" >&2
  return 1
}

start_backend() {
  if test_tcp_port; then
    printf 'Backend port %s:%s is already in use.\n' "$backend_host" "$backend_port" >&2
    return 1
  fi

  printf 'Starting backend at http://%s:%s ...\n' "$backend_host" "$backend_port"
  (
    cd "$project_root"
    exec fvm dart run --enable-experiment=native-assets bin/server.dart \
      --host "$backend_host" --port "$backend_port"
  ) &
  backend_pid=$!

  if ! wait_backend; then
    stop_process_tree "$backend_pid"
    backend_pid=""
    return 1
  fi

  printf 'Backend is ready (PID %s).\n' "$backend_pid"
}

restart_backend() {
  printf 'Restarting backend ...\n'
  stop_process_tree "$backend_pid"
  backend_pid=""
  start_backend
  printf 'Frontend is available at http://localhost:%s\n' "$frontend_port"
}

start_frontend() {
  printf 'Starting frontend at http://localhost:%s ...\n' "$frontend_port"
  (
    cd "$project_root"
    exec pnpm --dir host-deck-ui dev
  ) >/dev/null 2>&1 &
  frontend_pid=$!
  printf 'Frontend started (PID %s).\n' "$frontend_pid"
}

cleanup() {
  printf 'Stopping development services ...\n'
  stop_process_tree "$frontend_pid"
  stop_process_tree "$backend_pid"
}

trap cleanup EXIT INT TERM

start_backend
start_frontend

printf '\nPress [r] to restart backend, [q] to quit.\n'
while IFS= read -r -n 1 key; do
  case "$key" in
    [Rr]) restart_backend ;;
    [Qq]) break ;;
  esac
done
