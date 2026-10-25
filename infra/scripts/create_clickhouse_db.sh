#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
infra_dir="$(dirname "$script_dir")"

if [[ -f "$infra_dir/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$infra_dir/.env"
    set +a
fi

host="${CLICKHOUSE_HTTP_HOST:-127.0.0.1}"
port="${CLICKHOUSE_PORT:-8123}"
database="${CLICKHOUSE_DATABASE:-analytics}"
username="${CLICKHOUSE_USERNAME:-default}"
password="${CLICKHOUSE_PASSWORD:-}"
base_url="http://${host}:${port}"

until curl --fail --silent --user "${username}:${password}" "${base_url}/ping" >/dev/null; do
    echo "Waiting for ClickHouse at ${base_url}..."
    sleep 2
done

curl --fail --silent --show-error \
    --user "${username}:${password}" \
    --data-binary "CREATE DATABASE IF NOT EXISTS \`${database}\`" \
    "${base_url}/" >/dev/null

curl --fail --silent --show-error \
    --user "${username}:${password}" \
    --data-binary "@${script_dir}/init_clickhouse.sql" \
    "${base_url}/?database=${database}&multiquery=1" >/dev/null

echo "ClickHouse database and tables are ready."
