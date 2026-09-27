#!/usr/bin/env bash
# Builds the canvas and copies it into the running dev container's /opt/sentai-web, the folder
# sentai.web.StaticFiles serves (the image bakes it at build time; this refreshes it in place).
set -euo pipefail
cd "$(dirname "$0")/../frontend"
container="${SENTAI_CONTAINER:-sentai-task-iris-1}"
npm run build >/dev/null
docker cp build/. "$container:/opt/sentai-web/"
MSYS_NO_PATHCONV=1 docker exec -u root "$container" chown -R irisowner:irisowner /opt/sentai-web
echo "published to $container:/opt/sentai-web"
