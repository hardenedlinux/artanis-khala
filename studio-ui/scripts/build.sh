#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TSC="$ROOT/node_modules/typescript/bin/tsc"
if [[ ! -f "$TSC" ]]; then
  echo "Local TypeScript compiler not found. Run (cd studio-ui && npm install) first." >&2
  exit 1
fi
if ! command -v node >/dev/null 2>&1; then
  echo "Node.js was not found in PATH." >&2
  exit 1
fi
if [[ ! -f node_modules/react/umd/react.production.min.js || ! -f node_modules/react-dom/umd/react-dom.production.min.js ]]; then
  echo "React runtime not found. Run npm install first." >&2
  exit 1
fi

mkdir -p dist/vendor
node "$TSC" -p tsconfig.json --pretty false
cp src/styles.css dist/studio-ui.css
cp node_modules/react/umd/react.production.min.js dist/vendor/react.production.min.js
cp node_modules/react-dom/umd/react-dom.production.min.js dist/vendor/react-dom.production.min.js
cp integration/studio-view.html dist/index.html

echo "Built standalone Studio view: dist/index.html + dist/studio-ui.js + dist/studio-ui.css + dist/vendor/"
