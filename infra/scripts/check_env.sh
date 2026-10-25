#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker is not installed or is not in PATH" >&2
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    echo "ERROR: Docker Compose v2 is unavailable" >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon is not running" >&2
    exit 1
fi

if [[ ! -f infra/.env ]]; then
    echo "ERROR: infra/.env is missing. Copy infra/env.example and set secrets." >&2
    exit 1
fi

docker compose --env-file infra/.env -f infra/docker-compose.yml config --quiet
echo "Environment and Docker Compose configuration are valid."
