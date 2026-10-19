#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

action="${1:-}"
instance="${2:-}"
[[ "$instance" == 1 || "$instance" == 2 ]] || fail 'Использование: backend.sh start|stop|status 1|2'
case "$instance" in
    1) port="$BACKEND1_PORT" ;;
    2) port="$BACKEND2_PORT" ;;
esac
pid_file="$RUN_DIR/backend-$instance.pid"
log_file="$RUN_DIR/logs/backend-$instance.log"
app_file="$REPO_DIR/lab-0/backend/app.py"

is_running() {
    [[ -f "$pid_file" ]] || return 1
    local pid command
    pid="$(cat "$pid_file")"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    command="$(ps -p "$pid" -o command=)"
    [[ "$command" == *"$app_file"* && "$command" == *"--port=$port"* ]]
}

case "$action" in
    start)
        if is_running; then
            printf 'backend-%s уже запущен (PID %s)\n' "$instance" "$(cat "$pid_file")"
            exit 0
        fi
        [[ -x "$RUN_DIR/venv/bin/python" ]] || fail 'Сначала выполните scripts/setup.sh'
        mkdir -p "$RUN_DIR/logs"
        # Создаём таблицу до параллельного обслуживания запросов двумя процессами.
        "$RUN_DIR/venv/bin/python" - "$app_file" <<'PY'
import runpy
import sys
runpy.run_path(sys.argv[1])['init_db']()
PY
        # Отдельная сессия сохраняет процесс после закрытия запускающего терминала.
        "$RUN_DIR/venv/bin/python" - "$app_file" "$port" "$instance" "$log_file" "$pid_file" <<'PY'
import os
from pathlib import Path
import subprocess
import sys

app, port, instance, log_file, pid_file = sys.argv[1:]
env = dict(os.environ, INSTANCE_ID=f'backend-{instance}', FLASK_SKIP_DOTENV='1', FLASK_DEBUG='0')
with open(log_file, 'w') as log:
    process = subprocess.Popen(
        [sys.executable, '-m', 'flask', '--app', app, 'run',
         '--host=127.0.0.1', f'--port={port}', '--no-debugger', '--no-reload'],
        env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
        start_new_session=True,
    )
Path(pid_file).write_text(f'{process.pid}\n')
PY
        for attempt in {1..50}; do
            if ! is_running; then
                fail "backend-$instance не запустился; см. $log_file"
            fi
            if "$CURL_BIN" --noproxy '*' -fsS --max-time 2 "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
                printf 'backend-%s: 127.0.0.1:%s (PID %s), health=200\n' "$instance" "$port" "$(cat "$pid_file")"
                exit 0
            fi
            sleep 0.2
        done
        "$0" stop "$instance"
        fail "backend-$instance: проверка /health не прошла; см. $log_file"
        ;;
    stop)
        if ! is_running; then
            printf 'backend-%s не запущен этим скриптом\n' "$instance"
            exit 0
        fi
        pid="$(cat "$pid_file")"
        kill -TERM "$pid"
        for attempt in {1..50}; do
            if ! kill -0 "$pid" 2>/dev/null; then
                rm -f "$pid_file"
                printf 'backend-%s остановлен\n' "$instance"
                exit 0
            fi
            sleep 0.1
        done
        fail "backend-$instance не завершился (PID $pid)"
        ;;
    status)
        is_running || fail "backend-$instance не запущен"
        printf 'backend-%s: PID %s, port %s\n' "$instance" "$(cat "$pid_file")" "$port"
        ;;
    *) fail 'Использование: backend.sh start|stop|status 1|2' ;;
esac
