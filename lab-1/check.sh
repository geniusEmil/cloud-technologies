#!/usr/bin/env bash
# Проверки обычной части: только собственные локальные сервисы.
set -euo pipefail
LAB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$LAB_DIR/scripts/common.sh"

umask 077
CHECK_TMP=$(mktemp -d "${TMPDIR:-/tmp}/lab1-check.XXXXXX")
RESTORE_BACKEND=0
cleanup() {
    local result=$?
    trap - EXIT
    if [[ "$RESTORE_BACKEND" == 1 ]]; then
        printf '\n+ scripts/backend.sh start 1 (восстановление после проверки)\n'
        if ! "$LAB_DIR/scripts/backend.sh" start 1; then
            printf 'FAIL: не удалось восстановить backend-1\n' >&2
            result=1
        fi
    fi
    rm -rf "$CHECK_TMP"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

TLS_ARGS=(
    --cacert "$RUN_DIR/tls/server.crt"
    --resolve "todo.localhost:$HTTP_PORT:127.0.0.1"
    --resolve "todo.localhost:$HTTPS_PORT:127.0.0.1"
    --resolve "other.localhost:$HTTP_PORT:127.0.0.1"
    --resolve "other.localhost:$HTTPS_PORT:127.0.0.1"
    --noproxy '*'
    --connect-timeout 3 --max-time 10
)
TODO_URL="https://todo.localhost:$HTTPS_PORT"
OTHER_URL="https://other.localhost:$HTTPS_PORT"

header() {
    awk -v wanted="$1" '
        { sub(/\r$/, "") }
        tolower($1) == tolower(wanted) ":" {
            sub(/^[^:]*:[[:space:]]*/, ""); print; exit
        }
    ' "$CHECK_TMP/headers"
}

request() {
    local url=$1
    shift
    sleep 0.25
    printf '\n+ %q' "$CURL_BIN"
    printf ' %q' --disable "${TLS_ARGS[@]}" "$@" "$url"
    printf '\n'
    if ! STATUS=$("$CURL_BIN" --disable -sS "${TLS_ARGS[@]}" "$@" \
        -D "$CHECK_TMP/headers" -o "$CHECK_TMP/body" \
        -w '%{http_code}' "$url"); then
        fail "curl: соединение или проверка TLS не прошли"
    fi
    INSTANCE=$(header X-Instance-Id)
    printf 'HTTP %s; X-Instance-Id: %s\n' "$STATUS" "${INSTANCE:--}"
}

expect_status() {
    [[ "$STATUS" == "$1" ]] || fail "ожидался HTTP $1, получен $STATUS"
}

printf 'Лаба 1: проверка nginx (%s)\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
printf 'TLS проверяется по локальному сертификату; curl без -k.\n'
printf 'Порты этого прогона: HTTP=%s, HTTPS=%s. По ТЗ: 80/443.\n' "$HTTP_PORT" "$HTTPS_PORT"
[[ -r "$RUN_DIR/tls/server.crt" ]] || fail "сначала выполните scripts/setup.sh"

printf '\n+ scripts/backend.sh status 1\n'
"$LAB_DIR/scripts/backend.sh" status 1 || fail "backend-1 должен быть запущен до проверки"
printf '\n+ scripts/backend.sh status 2\n'
"$LAB_DIR/scripts/backend.sh" status 2 || fail "backend-2 должен быть запущен до проверки"

request "http://todo.localhost:$HTTP_PORT/" --head
expect_status 301
LOCATION=$(header Location)
printf 'Location: %s\n' "$LOCATION"
if [[ "$HTTPS_PORT" == 443 ]]; then
    [[ "$LOCATION" == 'https://todo.localhost/' || "$LOCATION" == 'https://todo.localhost:443/' ]] \
        || fail "неверный адрес HTTPS-редиректа"
else
    [[ "$LOCATION" == "$TODO_URL/" ]] || fail "неверный адрес HTTPS-редиректа"
fi
pass 'HTTP перенаправляется на HTTPS (301)'

request "$TODO_URL/"
expect_status 200
[[ -z "$INSTANCE" ]] || fail "статика прошла через бэкенд"
pass 'TLS доверен; nginx сам отдаёт фронтенд'

request "$TODO_URL/docs/"
expect_status 200
grep -q 'lab1-docs' "$CHECK_TMP/body" || fail "не найден маркер отдельного каталога docs"
[[ -z "$INSTANCE" ]] || fail "docs прошёл через бэкенд"
pass 'alias /docs/ отдаёт отдельный каталог'

request "$OTHER_URL/"
expect_status 200
grep -q 'lab1-other' "$CHECK_TMP/body" || fail "второй домен не отдаёт свой проект"
[[ -z "$INSTANCE" ]] || fail "второй проект прошёл через бэкенд todo"
request "$OTHER_URL/api/tasks"
expect_status 404
[[ -z "$INSTANCE" ]] || fail "API первого проекта доступен на чужом домене"
request "$TODO_URL/" -H 'Host: unknown.localhost'
expect_status 404
[[ -z "$INSTANCE" ]] || fail "неизвестный Host попал на бэкенд"
pass 'виртуальные хосты изолированы; неизвестный Host получает 404'

request "$TODO_URL/admin"
expect_status 401
[[ "$(header WWW-Authenticate)" == Basic* ]] || fail "нет запроса Basic Authentication"
pass '/admin без пароля возвращает 401 и WWW-Authenticate'

if [[ -z "${LAB1_ADMIN_PASSWORD:-}" && -t 0 ]]; then
    read -r -s -p 'Пароль admin для проверки входа (Enter — пропустить): ' LAB1_ADMIN_PASSWORD || true
    printf '\n'
fi
if [[ -n "${LAB1_ADMIN_PASSWORD:-}" ]]; then
    # Передаём секрет через stdin в приватный файл, а не через argv или вывод.
    printf '%s:%s' "${LAB1_ADMIN_USER:-admin}" "$LAB1_ADMIN_PASSWORD" \
        | "$PYTHON_BIN" -c 'import base64, sys; print("header = \"Authorization: Basic " + base64.b64encode(sys.stdin.buffer.read()).decode("ascii") + "\"")' \
        > "$CHECK_TMP/auth.conf"
    request "$TODO_URL/admin" --config "$CHECK_TMP/auth.conf"
    expect_status 200
    rm -f "$CHECK_TMP/auth.conf"
    pass '/admin с правильными учётными данными возвращает 200'
else
    printf 'SKIP: вход с паролем (задайте LAB1_ADMIN_PASSWORD); защита без пароля проверена\n'
fi

request "$TODO_URL/this-page-does-not-exist"
expect_status 404
grep -q 'lab1-not-found' "$CHECK_TMP/body" || fail "ответ не содержит свою страницу 404"
pass 'несуществующая страница возвращает свою 404'

printf '\nПроверка балансировки: 8 последовательных запросов\n'
SEEN_1=0
SEEN_2=0
for ((i=1; i<=8; i++)); do
    request "$TODO_URL/api/tasks"
    expect_status 200
    case "$INSTANCE" in
        backend-1) SEEN_1=$((SEEN_1 + 1)) ;;
        backend-2) SEEN_2=$((SEEN_2 + 1)) ;;
        *) fail "неожиданный идентификатор инстанса: $INSTANCE" ;;
    esac
done
[[ "$SEEN_1" -gt 0 && "$SEEN_2" -gt 0 ]] || fail "запросы не распределились между обоими инстансами"
pass "балансировка: backend-1=$SEEN_1, backend-2=$SEEN_2"

printf '\n+ scripts/backend.sh stop 1\n'
# Флаг выставлен до stop, чтобы trap восстановил процесс и при прерывании.
RESTORE_BACKEND=1
"$LAB_DIR/scripts/backend.sh" stop 1
for ((i=1; i<=5; i++)); do
    request "$TODO_URL/api/tasks"
    expect_status 200
    [[ "$INSTANCE" == backend-2 ]] || fail "после остановки backend-1 ответил не backend-2"
done
request "$TODO_URL/"
expect_status 200
[[ -z "$INSTANCE" ]] || fail "фронтенд прошёл через бэкенд"
pass 'после остановки backend-1 API и фронтенд доступны'
printf '\n+ scripts/backend.sh start 1\n'
"$LAB_DIR/scripts/backend.sh" start 1
RESTORE_BACKEND=0

printf '\nПроверка limit_req: только локальный /api, всего 40 запросов, параллельность 10\n'
sleep 3
printf '+ printf "1..40" | xargs -P 10 -I REQUEST curl [те же TLS-параметры] %s/api/tasks\n' "$TODO_URL"
if ! (
    for ((i=1; i<=40; i++)); do printf '%s\n' "$i"; done
) | xargs -P 10 -I REQUEST "$CURL_BIN" --disable -sS "${TLS_ARGS[@]}" \
    -o /dev/null -w '%{http_code}\n' "$TODO_URL/api/tasks" > "$CHECK_TMP/flood-statuses"; then
    fail "ошибка соединения при ограниченной проверке limit_req"
fi
sort "$CHECK_TMP/flood-statuses" | uniq -c
[[ "$(wc -l < "$CHECK_TMP/flood-statuses" | tr -d ' ')" == 40 ]] || fail "получены не все 40 ответов"
grep -q '^429$' "$CHECK_TMP/flood-statuses" || fail "limit_req не вернул 429"
grep -q '^200$' "$CHECK_TMP/flood-statuses" || fail "limit_req отклонил все запросы"
if grep -Ev '^(200|429)$' "$CHECK_TMP/flood-statuses" >/dev/null; then
    fail "при нагрузке получены ответы, отличные от 200/429"
fi
pass 'limit_req ограничивает частоту ответами 429'
printf '\nPASS: функциональные проверки выполнены на HTTP=%s/HTTPS=%s; backend-1 восстановлен\n' "$HTTP_PORT" "$HTTPS_PORT"
