#!/usr/bin/env bash
# Stop the environment. --reset also deletes the database and demo dump volumes.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--reset" ]]; then
  docker compose --profile compasslink down --volumes
else
  docker compose --profile compasslink down
fi
