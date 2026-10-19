#!/usr/bin/env bash

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$LAB_DIR/.." && pwd)"
RUN_DIR="$LAB_DIR/.run"

if [[ -f "$LAB_DIR/.env" ]]; then
    set -a
    source "$LAB_DIR/.env"
    set +a
fi

: "${DB_HOST:=127.0.0.1}" "${DB_PORT:=5432}" "${DB_NAME:=todo}"
: "${DB_USER:=todo}" "${DB_PASSWORD:=}"
: "${HTTP_PORT:=80}" "${HTTPS_PORT:=443}"
: "${BACKEND1_PORT:=8000}" "${BACKEND2_PORT:=8001}"
: "${PYTHON_BIN:=python3}" "${NGINX_BIN:=nginx}" "${OPENSSL_BIN:=openssl}"
: "${CURL_BIN:=curl}" "${LAB1_ADMIN_USER:=admin}"
export DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD
export LAB_DIR REPO_DIR RUN_DIR HTTP_PORT HTTPS_PORT BACKEND1_PORT BACKEND2_PORT

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Не найдена команда: $1"
}
