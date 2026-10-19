#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

for command in "$PYTHON_BIN" "$NGINX_BIN" "$OPENSSL_BIN" htpasswd; do
    require_command "$command"
done
umask 077
mkdir -p "$RUN_DIR/tls" "$RUN_DIR/logs" "$RUN_DIR/client_temp" "$RUN_DIR/proxy_temp"

if [[ ! -x "$RUN_DIR/venv/bin/python" ]]; then
    "$PYTHON_BIN" -m venv "$RUN_DIR/venv"
fi
"$RUN_DIR/venv/bin/python" -m pip install -r "$REPO_DIR/lab-0/backend/requirements.txt"

if [[ ! -f "$RUN_DIR/tls/server.crt" || ! -f "$RUN_DIR/tls/server.key" ]]; then
    "$OPENSSL_BIN" req -x509 -newkey rsa:2048 -nodes -sha256 -days 30 \
        -keyout "$RUN_DIR/tls/server.key" -out "$RUN_DIR/tls/server.crt" \
        -subj '/CN=todo.localhost' \
        -addext 'subjectAltName=DNS:todo.localhost,DNS:other.localhost,DNS:localhost,IP:127.0.0.1'
fi

if [[ ! -f "$RUN_DIR/htpasswd" ]]; then
    if [[ -n "${LAB1_ADMIN_PASSWORD:-}" ]]; then
        printf '%s\n' "$LAB1_ADMIN_PASSWORD" | htpasswd -ci "$RUN_DIR/htpasswd" "$LAB1_ADMIN_USER"
    else
        htpasswd -c "$RUN_DIR/htpasswd" "$LAB1_ADMIN_USER"
    fi
fi

export WORKER_USER="${SUDO_USER:-$(id -un)}"
export WORKER_GROUP="$(id -gn "$WORKER_USER")"
"$RUN_DIR/venv/bin/python" - <<'PY'
import os
from pathlib import Path

lab = Path(os.environ['LAB_DIR'])
names = ('LAB_DIR', 'REPO_DIR', 'HTTP_PORT', 'HTTPS_PORT', 'BACKEND1_PORT',
         'BACKEND2_PORT', 'WORKER_USER', 'WORKER_GROUP')
values = {name: os.environ[name] for name in names}
for name in ('HTTP_PORT', 'HTTPS_PORT', 'BACKEND1_PORT', 'BACKEND2_PORT'):
    value = values[name]
    if not value.isdecimal() or not 1 <= int(value) <= 65535:
        raise SystemExit(f'Invalid port: {name}')
values['HTTPS_SUFFIX'] = '' if values['HTTPS_PORT'] == '443' else ':' + values['HTTPS_PORT']
config = (lab / 'nginx/nginx.conf.template').read_text()
for name, value in values.items():
    if any(char in value for char in ('"', '\n', '\r', '$', '\\')):
        raise SystemExit(f'Unsupported character in {name}')
    config = config.replace('@' + name + '@', value)
(lab / '.run/nginx.conf').write_text(config)
PY

printf '\nГотово. Конфиг: %s/nginx.conf\n' "$RUN_DIR"
printf 'Проверка и запуск: sudo ./scripts/nginx.sh test && sudo ./scripts/nginx.sh start\n'
