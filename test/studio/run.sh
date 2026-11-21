#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
run_dir=${KHALA_STUDIO_RUN_DIR:-$(mktemp -d /tmp/khala-studio-test.XXXXXX)}
port=${KHALA_STUDIO_TEST_PORT:-$((3200 + $$ % 400))}
state="$run_dir/state.json"
config="$run_dir/khala.conf"
server_pid=

cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

sed -e "s|^studio_db = .*|studio_db = $run_dir/studio.sqlite3|" \
    -e "s|^studio_assets_dir = .*|studio_assets_dir = $run_dir/studio-assets|" \
    -e "s|^history_db = .*|history_db = $run_dir/history.sqlite3|" \
    -e 's|^engine = .*|engine = fake|' \
    -e 's|^studio_model = .*|studio_model = fake|' \
    "$root/conf/khala.conf" > "$config"

start_server() {
  (cd "$root" && GUILE_AUTO_COMPILE=0 KHALA_CONFIG="$config" \
    art work -h 127.0.0.1 -p "$port" >"$run_dir/server.log" 2>&1) &
  server_pid=$!
  ready=0
  count=0
  while [ "$count" -lt 200 ]; do
    if curl --noproxy '*' -fsS --max-time 1 \
        "http://127.0.0.1:$port/api/version" >/dev/null 2>&1; then
      ready=1
      break
    fi
    count=$((count + 1))
    sleep 0.1
  done
  if [ "$ready" -ne 1 ]; then
    echo "Khala Studio test server failed to start"
    tail -40 "$run_dir/server.log" || true
    exit 1
  fi
}

stop_server() {
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  server_pid=
}

if ! command -v art >/dev/null 2>&1; then
  echo "art is required" >&2
  exit 1
fi

GUILE_AUTO_COMPILE=0 GUILE_LOAD_PATH="$root/lib:$root" \
  guile "$root/test/studio/storyboard.scm"
GUILE_AUTO_COMPILE=0 GUILE_LOAD_PATH="$root/lib:$root" \
  guile "$root/test/studio/character_studio.scm"
GUILE_AUTO_COMPILE=0 GUILE_LOAD_PATH="$root/lib:$root" \
  guile "$root/test/studio/visual_consistency.scm"

start_server
KHALA_STUDIO_TEST_PORT="$port" KHALA_STUDIO_STATE="$state" \
  KHALA_STUDIO_TEST_ASSETS_DIR="$run_dir/studio-assets" \
  python3 "$root/test/studio/api.py"
if command -v node >/dev/null 2>&1 && [ -f "$root/ui/node_modules/playwright/index.js" ]; then
  KHALA_STUDIO_TEST_PORT="$port" node "$root/test/studio/browser.mjs"
else
  echo "Playwright is not installed under ui/node_modules; skipping browser smoke test"
fi
stop_server

# Every Studio operation opens its own DBI connection, but a real backend
# restart is still checked explicitly for the acceptance criterion.
start_server
KHALA_STUDIO_TEST_PORT="$port" KHALA_STUDIO_STATE="$state" \
  python3 "$root/test/studio/restart.py"
stop_server

echo "Studio restart persistence passed"
