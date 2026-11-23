#!/usr/bin/env bash
# Block until DHIS2 answers /api/system/info with the demo admin credentials.
set -euo pipefail
URL="${DHIS2_BASE_URL:-http://localhost:8080}"
for i in $(seq 1 120); do
  if curl -fsu "${DHIS2_USERNAME:-admin}:${DHIS2_PASSWORD:-district}" "$URL/api/system/info" >/dev/null 2>&1; then
    curl -fsu "${DHIS2_USERNAME:-admin}:${DHIS2_PASSWORD:-district}" "$URL/api/system/info" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("DHIS2",d["version"],"ready")'
    exit 0
  fi
  sleep 10
done
echo "DHIS2 not ready after 20 min" >&2; exit 1
