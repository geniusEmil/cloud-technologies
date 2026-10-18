# Лабораторная 0: веб-сервис списка задач

Небольшое веб-приложение: на странице можно добавить задачу (и удалить её крестиком), задачи хранятся в PostgreSQL. После перезагрузки страницы или перезапуска бэкенда задачи остаются на месте.

## Из чего состоит

```
браузер ──HTTP──> Flask (backend/app.py) ──TCP 5432──> PostgreSQL
   │                 │
   └── index.html, script.js, style.css (отдаёт тот же Flask по "/")
```

| Часть | Где лежит | Что делает |
|---|---|---|
| Фронтенд | `frontend/` | Статическая страница: форма и список задач. Ходит в API через `fetch` по относительному пути `/api/tasks`. |
| Бэкенд | `backend/app.py` | Flask-приложение. Принимает и отдаёт задачи в JSON, пишет их в БД через `psycopg2`. |
| База данных | отдельный сервис PostgreSQL | Хранит таблицу `tasks`. Бэкенд создаёт таблицу сам при старте (`CREATE TABLE IF NOT EXISTS`). |

### API

| Метод и путь | Что делает | Ответ |
|---|---|---|
| `GET /api/tasks` | список задач, новые сверху | `200 {"tasks": [...], "instance_id": "..."}` |
| `POST /api/tasks` | добавить задачу, тело `{"text": "..."}` | `201 {"task": {...}, "instance_id": "..."}`; `400` при пустом тексте или не-JSON |
| `DELETE /api/tasks/<id>` | удалить задачу по номеру | `200 {"deleted": id, "instance_id": "..."}`; `404`, если такой задачи нет |
| `GET /health` | проверка живости, делает `SELECT 1` в БД | `200`, если БД отвечает, иначе `503` |

Каждый ответ содержит поле `instance_id` и заголовок `X-Instance-Id` со значением из переменной `INSTANCE_ID`. Это понадобится в следующих лабах, чтобы видеть, какой экземпляр бэкенда ответил. Если БД недоступна, API отвечает `503 {"error": "database unavailable"}` и не падает.

## Зависимости

- Python 3.10+ (проверялось на 3.12)
- PostgreSQL (проверялось на 16, установлен через Homebrew)
- Python-пакеты из `backend/requirements.txt`: Flask и psycopg2-binary

## Переменные окружения

| Переменная | Назначение | Пример |
|---|---|---|
| `DB_HOST` | адрес PostgreSQL | `localhost` |
| `DB_PORT` | порт PostgreSQL | `5432` |
| `DB_NAME` | имя базы | `todo` |
| `DB_USER` | пользователь БД | `todo` |
| `DB_PASSWORD` | пароль пользователя БД | задаёте сами |
| `PORT` | порт, на котором слушает бэкенд (адрес всегда `0.0.0.0`) | `8000` |
| `INSTANCE_ID` | имя экземпляра для ответов API | `backend-1` |

Шаблон лежит в `.env.example`. Настоящий `.env` с паролем в git не коммитится.

> На macOS порт 5000 часто занят AirPlay Receiver, поэтому по умолчанию используется 8000.

## Запуск

Все команды выполняются из папки `lab-0`.

### 1. PostgreSQL

macOS (Homebrew):

```bash
brew install postgresql@16
brew services start postgresql@16
```

Linux (Debian/Ubuntu): `sudo apt install postgresql`, дальше команды `psql` выполнять через `sudo -u postgres psql`.

Создать пользователя и базу (пароль придумайте свой):

```bash
psql -d postgres -c "CREATE USER todo WITH PASSWORD 'ваш_пароль';" -c "CREATE DATABASE todo OWNER todo;"
```

Если `psql` не находится, на macOS он лежит в `/opt/homebrew/opt/postgresql@16/bin/psql`.

### 2. Настройки

```bash
cp .env.example .env
```

В `.env` впишите пароль из предыдущего шага в `DB_PASSWORD`.

### 3. Бэкенд

```bash
python3 -m venv venv
./venv/bin/pip install -r backend/requirements.txt
set -a; source .env; set +a
./venv/bin/python backend/app.py
```

`set -a; source .env; set +a` загружает переменные из `.env` в окружение текущего терминала.

### 4. Страница

Откройте http://localhost:8000/ — бэкенд сам отдаёт файлы из `frontend/`.

### Второй экземпляр

В другом терминале (после `set -a; source .env; set +a`):

```bash
PORT=8001 INSTANCE_ID=backend-2 ./venv/bin/python backend/app.py
```

Оба экземпляра работают с одной базой, поэтому видят одни и те же задачи, но в ответах будут разные `instance_id`.

## Как проверить, что задача сохраняется

1. Откройте http://localhost:8000/, введите текст и нажмите «Добавить» — задача появится в списке.
2. Обновите страницу (F5) — задача на месте.
3. Остановите бэкенд (Ctrl+C), запустите снова и обновите страницу — задача всё ещё на месте, потому что лежит в PostgreSQL, а не в памяти процесса.

То же через curl:

```bash
curl -i http://localhost:8000/health
curl -i -X POST http://localhost:8000/api/tasks -H 'Content-Type: application/json' -d '{"text": "Купить молоко"}'
curl -i http://localhost:8000/api/tasks
```

Посмотреть данные прямо в базе:

```bash
psql -h localhost -U todo -d todo -c 'SELECT * FROM tasks;'
```

Результаты проверок и скриншоты — в [REPORT.md](REPORT.md).
