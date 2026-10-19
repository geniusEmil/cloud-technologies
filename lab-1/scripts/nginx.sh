#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_command "$NGINX_BIN"
[[ -f "$RUN_DIR/nginx.conf" ]] || fail 'Сначала выполните scripts/setup.sh'

case "${1:-}" in
    test)
        "$NGINX_BIN" -p "$RUN_DIR/" -c "$RUN_DIR/nginx.conf" -t ;;
    start)
        "$NGINX_BIN" -p "$RUN_DIR/" -c "$RUN_DIR/nginx.conf" -t
        "$NGINX_BIN" -p "$RUN_DIR/" -c "$RUN_DIR/nginx.conf"
        printf 'nginx: HTTP %s, HTTPS %s\n' "$HTTP_PORT" "$HTTPS_PORT" ;;
    reload)
        "$NGINX_BIN" -p "$RUN_DIR/" -c "$RUN_DIR/nginx.conf" -t
        "$NGINX_BIN" -p "$RUN_DIR/" -c "$RUN_DIR/nginx.conf" -s reload ;;
    stop)
        "$NGINX_BIN" -p "$RUN_DIR/" -c "$RUN_DIR/nginx.conf" -s quit ;;
    *) fail 'Использование: nginx.sh test|start|reload|stop' ;;
esac
