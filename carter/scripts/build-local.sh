#!/usr/bin/env bash
# Build a DHIS2 image from this fork's source (needs JDK 17 + Maven 3.9 + Docker).
set -euo pipefail
cd "$(dirname "$0")/../.."
TAG="${1:-carter/dhis2-core:2.43.2.1-carter}"
mvn clean package -DskipTests -Dmaven.test.skip=true --file dhis-2/pom.xml \
  --projects dhis-web-server --also-make --activate-profiles jibDockerBuild \
  -Djib.to.image="$TAG"
echo "Built $TAG — set DHIS2_IMAGE=$TAG in carter/.env"
