#!/usr/bin/env bash
set -euo pipefail

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
NODE_VERSION="${NODE_VERSION:-24.22.0}"

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  echo "nvm was not found at $NVM_DIR" >&2
  echo "Install nvm first or set NVM_DIR to its directory." >&2
  exit 1
fi

. "$NVM_DIR/nvm.sh"
nvm install "$NODE_VERSION"
nvm alias default "$NODE_VERSION"
nvm use "$NODE_VERSION"
hash -r

node --version
npm --version
