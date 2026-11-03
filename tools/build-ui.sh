#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root/ui"
if ! npm ci; then
  npm ci --registry=https://registry.npmmirror.com
fi
npm run build
