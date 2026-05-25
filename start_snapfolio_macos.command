#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
FRONTEND_DIR="$ROOT_DIR/frontend"

BACKEND_HOST="${BACKEND_HOST:-127.0.0.1}"
BACKEND_PORT="${BACKEND_PORT:-8000}"
FRONTEND_HOST="${FRONTEND_HOST:-127.0.0.1}"
FRONTEND_PORT="${FRONTEND_PORT:-5173}"
API_BASE_URL="${API_BASE_URL:-http://$BACKEND_HOST:$BACKEND_PORT}"
FRONTEND_URL="http://$FRONTEND_HOST:$FRONTEND_PORT"

PYTHON_BIN="${PYTHON_BIN:-$BACKEND_DIR/.venv/bin/python}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
SKIP_INSTALL="${SKIP_INSTALL:-0}"
BACKEND_RELOAD="${BACKEND_RELOAD:-0}"

BACKEND_LOG="$ROOT_DIR/.backend_run.macos.log"
FRONTEND_LOG="$ROOT_DIR/.frontend_run.macos.log"
BACKEND_PID=""
FRONTEND_PID=""

die() {
  echo "Error: $*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

port_is_open() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

stop_process_tree() {
  local pid="$1"
  if kill -0 "$pid" >/dev/null 2>&1; then
    pkill -TERM -P "$pid" >/dev/null 2>&1 || true
    kill -TERM "$pid" >/dev/null 2>&1 || true
  fi
}

cleanup() {
  if [ -n "$FRONTEND_PID" ]; then
    stop_process_tree "$FRONTEND_PID"
  fi
  if [ -n "$BACKEND_PID" ]; then
    stop_process_tree "$BACKEND_PID"
  fi
}

wait_for_port() {
  local port="$1"
  local timeout_seconds="$2"
  local elapsed=0

  while ! port_is_open "$port"; do
    if [ "$elapsed" -ge "$timeout_seconds" ]; then
      return 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
}

wait_for_backend() {
  local timeout_seconds="$1"
  local elapsed=0

  if ! command_exists curl; then
    wait_for_port "$BACKEND_PORT" "$timeout_seconds"
    return
  fi

  while ! curl -fsS "$API_BASE_URL/health" >/dev/null 2>&1; do
    if [ "$elapsed" -ge "$timeout_seconds" ]; then
      return 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
}

ensure_backend() {
  [ -f "$BACKEND_DIR/app/main.py" ] || die "Backend application was not found in $BACKEND_DIR"

  if [ ! -x "$PYTHON_BIN" ]; then
    if [ "$SKIP_INSTALL" = "1" ]; then
      die "Backend Python environment was not found at $PYTHON_BIN"
    fi
    command_exists python3 || die "python3 was not found. Install Python 3 and run this script again."
    echo "Creating backend virtual environment..."
    python3 -m venv "$BACKEND_DIR/.venv"
    PYTHON_BIN="$BACKEND_DIR/.venv/bin/python"
  fi

  if [ "$SKIP_INSTALL" != "1" ]; then
    echo "Installing backend dependencies..."
    "$PYTHON_BIN" -m pip install --upgrade pip
    "$PYTHON_BIN" -m pip install -r "$BACKEND_DIR/requirements.txt"
  fi
}

ensure_frontend() {
  [ -f "$FRONTEND_DIR/pubspec.yaml" ] || die "Frontend application was not found in $FRONTEND_DIR"

  if ! command_exists "$FLUTTER_BIN"; then
    die "Flutter was not found. Install Flutter or set FLUTTER_BIN to the Flutter executable path."
  fi

  if [ "$SKIP_INSTALL" != "1" ]; then
    echo "Installing frontend dependencies..."
    (cd "$FRONTEND_DIR" && "$FLUTTER_BIN" pub get)
  fi
}

start_backend() {
  if port_is_open "$BACKEND_PORT"; then
    echo "Backend port $BACKEND_PORT is already in use. Skipping backend start."
    return
  fi

  local backend_args=(-m uvicorn app.main:app --host "$BACKEND_HOST" --port "$BACKEND_PORT")
  if [ "$BACKEND_RELOAD" = "1" ]; then
    backend_args+=(--reload)
  fi

  echo "Starting backend on $API_BASE_URL..."
  (cd "$BACKEND_DIR" && "$PYTHON_BIN" "${backend_args[@]}" >"$BACKEND_LOG" 2>&1) &
  BACKEND_PID="$!"
}

start_frontend() {
  if port_is_open "$FRONTEND_PORT"; then
    echo "Frontend port $FRONTEND_PORT is already in use. Skipping frontend start."
    return
  fi

  local flutter_args=(
    run
    -d web-server
    --web-hostname "$FRONTEND_HOST"
    --web-port "$FRONTEND_PORT"
    --dart-define="API_BASE_URL=$API_BASE_URL"
  )

  echo "Starting frontend on $FRONTEND_URL..."
  (cd "$FRONTEND_DIR" && "$FLUTTER_BIN" "${flutter_args[@]}" >"$FRONTEND_LOG" 2>&1) &
  FRONTEND_PID="$!"
}

trap cleanup INT TERM EXIT

ensure_backend
ensure_frontend
start_backend

if ! wait_for_backend 60; then
  echo "Backend did not become ready within 60 seconds."
  echo "Backend log: $BACKEND_LOG"
  exit 1
fi

start_frontend

if ! wait_for_port "$FRONTEND_PORT" 120; then
  echo "Frontend did not become ready within 120 seconds."
  echo "Frontend log: $FRONTEND_LOG"
  exit 1
fi

echo ""
echo "SnapFolio is running."
echo "Frontend: $FRONTEND_URL"
echo "Backend docs: $API_BASE_URL/docs"
echo "Backend log: $BACKEND_LOG"
echo "Frontend log: $FRONTEND_LOG"
echo ""
echo "Press Ctrl+C to stop services started by this script."

if command_exists open; then
  open "$FRONTEND_URL" >/dev/null 2>&1 || true
fi

if [ -n "$BACKEND_PID" ] || [ -n "$FRONTEND_PID" ]; then
  wait
fi
