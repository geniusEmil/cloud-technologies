# Лабораторная 1 с nginx

nginx отдаёт фронтенд из лабы 0 по HTTPS и распределяет запросы `/api` между двумя экземплярами Flask, поэтому после остановки одного бэкенда запросы обслуживает второй. Стенд использует локальные процессы и общую PostgreSQL, Docker относится к лабе 2.

```text
браузер → nginx 127.0.0.1:80 → 301 → HTTPS 127.0.0.1:443
            │
            ├─ todo.localhost
            │    ├─ /          → lab-0/frontend/
            │    ├─ /api/*     → Flask 127.0.0.1:8000 ─┐
            │    │             → Flask 127.0.0.1:8001 ─┤→ PostgreSQL
            │    ├─ /docs/     → отдельный каталог
            │    └─ /admin     → страница с Basic Auth
            │
            └─ other.localhost → второй статический сайт
```

Порты nginx и обоих бэкендов доступны только на `127.0.0.1`. Скрипт `setup.sh` подставляет пути и порты из настроек в [шаблон nginx](nginx/nginx.conf.template) и сохраняет результат в `.run/nginx.conf`. Второй домен обслуживает свой проект, неизвестный Host получает 404.

## Подготовка

Все команды выполняются из `lab-1/`. Нужны Bash, curl, Python 3.10+, PostgreSQL, nginx с HTTP SSL, OpenSSL и `htpasswd`.

На macOS установите зависимости через Homebrew.

```bash
brew install nginx python@3.12 postgresql@16 openssl
```

Проверьте наличие `htpasswd` командой `command -v htpasswd`. Если его нет, установите `brew install httpd` и добавьте `$(brew --prefix httpd)/bin` в `PATH`, запускать Apache для этого не требуется.

На Debian или Ubuntu используйте системные пакеты.

```bash
sudo apt update
sudo apt install nginx python3-venv postgresql openssl apache2-utils curl
```

Освободите порты 80, 443, 8000 и 8001, завершив ранее запущенные процессы Flask из лабы 0. Если установка nginx запустила ваш учебный системный экземпляр на порту 80, остановите его через `sudo systemctl stop nginx` на Linux или `brew services stop nginx` на macOS. При занятых другими проектами портах выберите свободное окружение.

### PostgreSQL

Оба бэкенда используют базу и пользователя из [лабы 0](../lab-0/README.md#1-postgresql). Для уже работающей базы достаточно перенести параметры подключения в `.env`.

При новой установке на macOS запустите PostgreSQL и откройте консоль.

```bash
brew services start postgresql@16
"$(brew --prefix postgresql@16)/bin/psql" -d postgres
```

На Debian или Ubuntu консоль открывается командой `sudo -u postgres psql`, при необходимости служба запускается через `sudo systemctl start postgresql`.

Создайте пользователя и базу в консоли `psql`, введя пароль по приглашению.

```sql
CREATE ROLE todo LOGIN;
\password todo
CREATE DATABASE todo OWNER todo;
\q
```

Бэкенд создаёт таблицу `tasks` при запуске. Команда `psql -h 127.0.0.1 -U todo -d todo -c 'SELECT 1;'` позволяет проверить подключение по TCP и запрашивает пароль интерактивно.

### Настройки и сертификат

```bash
cp .env.example .env
```

В `.env` укажите `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` и `DB_PASSWORD` своей базы. Файл загружается Bash через `source`, поэтому значения с пробелами или специальными символами заключайте в одинарные кавычки. По ТЗ используются `HTTP_PORT=80` и `HTTPS_PORT=443`, порты бэкендов по умолчанию равны 8000 и 8001.

Через `PYTHON_BIN`, `NGINX_BIN` и `OPENSSL_BIN` можно задать команду или абсолютный путь к программе. На macOS подойдут `PYTHON_BIN=python3.12` и путь к OpenSSL из `brew --prefix openssl@3` с окончанием `/bin/openssl`. Для nginx при запуске через `sudo` укажите в `NGINX_BIN` абсолютный путь из `command -v nginx`.

```bash
./scripts/setup.sh
```

Скрипт создаёт виртуальное окружение, устанавливает зависимости лабы 0, генерирует конфигурацию, самоподписанный сертификат на 30 дней и файл `htpasswd`. Сертификат содержит SAN для `todo.localhost`, `other.localhost`, `localhost` и `127.0.0.1`, пароль пользователя `admin` вводится по приглашению.

Повторный запуск сохраняет существующие сертификат и пароль. Пароль меняется командой `htpasswd .run/htpasswd admin`. Для обновления истёкшего сертификата удалите `.run/tls/server.crt` и `.run/tls/server.key`, затем повторите `setup.sh`. Каталоги и файлы с секретами `.env` и `.run/` исключены из Git.

## Запуск

```bash
./scripts/backend.sh start 1
./scripts/backend.sh start 2
sudo ./scripts/nginx.sh test
sudo ./scripts/nginx.sh start
```

Для nginx на портах 80/443 используйте `sudo`, включая проверку конфигурации, остановку и перезагрузку. Скрипт `start` выполняет `nginx -t` перед запуском. Подготовку и бэкенды запускайте обычным пользователем.

Откройте [сервис задач](https://todo.localhost/) и [второй сайт](https://other.localhost/). Если имена не разрешаются, добавьте запись в `/etc/hosts`.

```text
127.0.0.1 todo.localhost other.localhost
```

Браузер предупредит о самоподписанном сертификате, для своего локального стенда можно подтвердить исключение после проверки адреса. В командах curl имя и сертификат проверяются через `--cacert`, параметр `--resolve` направляет запросы на loopback без правки `/etc/hosts`.

```bash
curl --noproxy '*' --resolve todo.localhost:80:127.0.0.1 \
  -I http://todo.localhost/
curl --noproxy '*' --resolve todo.localhost:443:127.0.0.1 \
  --cacert .run/tls/server.crt -i https://todo.localhost/api/tasks
```

Первый запрос должен вернуть 301 на HTTPS. При повторении второго с небольшой паузой заголовок `X-Instance-Id` показывает `backend-1` и `backend-2`. После добавления задачи через страницу и обновления браузера запись сохраняется в общей PostgreSQL.

## Проверки и отчёт

```bash
mkdir -p docs
set -o pipefail
./check.sh 2>&1 | tee docs/check-output.txt
```

`check.sh` проверяет редирект, HTTPS, статику, `alias`, виртуальные хосты, свою 404, Basic Auth, балансировку, отказ бэкенда и ограничение частоты. Скрипт останавливает созданный `backend.sh` процесс `backend-1`, проверяет ответы второго экземпляра и восстанавливает первый, в том числе через `trap` при прерывании. Перед запуском нужны оба бэкенда, проверку выполняет создавший их пользователь.

Для проверки успешного входа в `/admin` введите пароль по приглашению. Пустой ответ отмечается `SKIP`, для автоматического запуска поддерживается `LAB1_ADMIN_PASSWORD` из окружения. Пароль должен оставаться вне команд, отчёта и Git. В прогоне на 80/443 проверен ответ 401 без пароля, успешный вход с ответом 200 подтверждён отдельным запросом, приведённым в [отчёте](REPORT.md#результаты-обычной-части).

После неудачного соединения `max_fails=1 fail_timeout=5s` временно исключает бэкенд, `proxy_next_upstream` позволяет направить запрос второму экземпляру. Проверяется отказ одного Flask-процесса при работающих nginx и общей PostgreSQL.

Результаты, выдержка из вывода и скриншоты приведены в [REPORT.md](REPORT.md). Журналы, создаваемые командой `tee`, остаются локально и исключены из Git. Внешние проверки для задания со звёздочкой описаны в отчёте.

## Остановка и диагностика

```bash
sudo ./scripts/nginx.sh stop
./scripts/backend.sh stop 1
./scripts/backend.sh stop 2
```

Общая PostgreSQL может продолжать работу. Статус бэкендов проверяется командами `./scripts/backend.sh status 1` и `./scripts/backend.sh status 2`, логи находятся в `.run/logs/backend-1.log` и `.run/logs/backend-2.log`. nginx пишет в `.run/error.log` и `.run/access.log`.

После изменения шаблона повторите `setup.sh` и выполните `sudo ./scripts/nginx.sh reload`. Перед изменением портов или параметров БД остановите стенд, измените `.env`, затем повторите подготовку и запуск.
