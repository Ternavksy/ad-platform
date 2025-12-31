#!/usr/bin/env bash
set -euo pipefail

echo "== Basic OS info =="
uname -a || true

echo "\n== Tool checks =="

check() {
    printf "%-20s" "$1"
    if command -v "$2" >/dev/null 2>&1; then
        echo "OK: $($2 --version 2>/dev/null | head -n1)"
    else
        echo "MISSING"
    fi
}

# Common tools
check "brew" brew
check "docker" docker
check "docker-compose" docker-compose
check "go" go
check "python3" python3
check "pip3" pip3
check "node" node
check "npm" npm

# DB clients (may not be in PATH)
printf "%-20s" "mysql"
if command -v mysql >/dev/null 2>&1; then
    mysql --version
else
    echo "MISSING"
fi

printf "%-20s" "clickhouse-client"
if command -v clickhouse-client >/dev/null 2>&1; then
    clickhouse-client --version
else
    echo "MISSING"
fi

printf "%-20s" "rabbitmqctl"
if command -v rabbitmqctl >/dev/null 2>&1; then
    rabbitmqctl status | head -n2
else
    echo "MISSING"
fi

printf "%-20s" "redis-cli"
if command -v redis-cli >/dev/null 2>&1; then
    redis-cli --version
else
    echo "MISSING"
fi

printf "%-20s" "tarantool"
if command -v tarantool >/dev/null 2>&1; then
    tarantool --version
else
    echo "MISSING"
fi

printf "%-20s" "ytsaurus"
# ytsaurus client may not be installed; placeholder
if command -v yt >/dev/null 2>&1; then
    yt version || true
else
    echo "MISSING"
fi

echo "\nIf some tools are MISSING, please install them via Homebrew (brew install ...) or Docker images."