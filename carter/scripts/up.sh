#!/usr/bin/env bash
# Start the Carter DHIS2 test environment. Pass --compasslink to include the connector.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] || { cp .env.example .env; echo "Created .env from .env.example — edit DB_PASSWORD."; }
profiles=()
[[ "${1:-}" == "--compasslink" ]] && profiles=(--profile compasslink)
docker compose "${profiles[@]}" up -d --build
echo "DHIS2 is starting at http://localhost:${DHIS2_PORT:-8080} (first boot with demo DB can take 5–15 min)."
echo "Follow logs: docker compose logs -f web"
