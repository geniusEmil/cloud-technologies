import os
from pathlib import Path

import psycopg2
from flask import Flask, jsonify, request, send_from_directory

# Вся конфигурация берётся из переменных окружения.
# Значения по умолчанию подходят только для локальной разработки.
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ.get("DB_NAME", "todo")
DB_USER = os.environ.get("DB_USER", "todo")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
PORT = int(os.environ.get("PORT", "8000"))
INSTANCE_ID = os.environ.get("INSTANCE_ID", "local")

MAX_TEXT_LENGTH = 500

# Папка со статикой фронтенда (нужна только для запуска без nginx)
FRONTEND_DIR = Path(__file__).resolve().parent.parent / "frontend"

app = Flask(__name__, static_folder=None)
# Кириллица в JSON без \uXXXX-экранирования
app.json.ensure_ascii = False


def get_connection():
    # Новое соединение на каждый запрос: просто и без пула
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=3,
    )


table_ready = False


def init_db():
    # Создаём таблицу, если её ещё нет
    global table_ready
    with get_connection() as conn, conn.cursor() as cur:
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS tasks (
                id SERIAL PRIMARY KEY,
                text TEXT NOT NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )
            """
        )
    conn.close()
    table_ready = True


def ensure_table():
    # Если при старте БД была недоступна, пробуем создать таблицу ещё раз
    if not table_ready:
        init_db()


def error(message, status):
    # Единый формат ошибки
    return jsonify({"error": message, "instance_id": INSTANCE_ID}), status


@app.after_request
def add_instance_header(response):
    # Каждый ответ помечаем идентификатором экземпляра
    response.headers["X-Instance-Id"] = INSTANCE_ID
    return response


@app.errorhandler(psycopg2.OperationalError)
def db_unavailable(exc):
    app.logger.error("БД недоступна: %s", exc)
    return error("database unavailable", 503)


@app.errorhandler(psycopg2.Error)
def db_error(exc):
    app.logger.error("Ошибка БД: %s", exc)
    return error("database error", 500)


@app.get("/health")
def health():
    # Проверяем, что БД отвечает на простой запрос
    try:
        conn = get_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
        conn.close()
    except psycopg2.Error:
        return jsonify({"status": "error", "db": "unavailable", "instance_id": INSTANCE_ID}), 503
    return jsonify({"status": "ok", "db": "ok", "instance_id": INSTANCE_ID})


@app.get("/api/tasks")
def list_tasks():
    ensure_table()
    conn = get_connection()
    with conn.cursor() as cur:
        cur.execute("SELECT id, text, created_at FROM tasks ORDER BY id DESC")
        rows = cur.fetchall()
    conn.close()
    tasks = [
        {"id": r[0], "text": r[1], "created_at": r[2].isoformat()} for r in rows
    ]
    return jsonify({"tasks": tasks, "instance_id": INSTANCE_ID})


@app.post("/api/tasks")
def create_task():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return error("expected JSON body like {\"text\": \"...\"}", 400)

    text = data.get("text")
    if not isinstance(text, str) or not text.strip():
        return error("task text must not be empty", 400)
    text = text.strip()
    if len(text) > MAX_TEXT_LENGTH:
        return error(f"task text is longer than {MAX_TEXT_LENGTH} characters", 400)

    ensure_table()
    conn = get_connection()
    with conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO tasks (text) VALUES (%s) RETURNING id, created_at",
            (text,),
        )
        task_id, created_at = cur.fetchone()
    conn.close()
    task = {"id": task_id, "text": text, "created_at": created_at.isoformat()}
    return jsonify({"task": task, "instance_id": INSTANCE_ID}), 201


@app.delete("/api/tasks/<int:task_id>")
def delete_task(task_id):
    ensure_table()
    conn = get_connection()
    with conn, conn.cursor() as cur:
        cur.execute("DELETE FROM tasks WHERE id = %s", (task_id,))
        deleted = cur.rowcount
    conn.close()
    if deleted == 0:
        return error("task not found", 404)
    return jsonify({"deleted": task_id, "instance_id": INSTANCE_ID})


@app.errorhandler(404)
def not_found(exc):
    return error("not found", 404)


@app.errorhandler(405)
def method_not_allowed(exc):
    return error("method not allowed", 405)


# Отдача статики для локального запуска без nginx
@app.get("/")
def index():
    return send_from_directory(FRONTEND_DIR, "index.html")


@app.get("/<path:filename>")
def static_files(filename):
    return send_from_directory(FRONTEND_DIR, filename)


if __name__ == "__main__":
    try:
        init_db()
    except psycopg2.Error as exc:
        # Не падаем: /health покажет проблему, запросы вернут 503
        app.logger.error("Не удалось создать таблицу при старте: %s", exc)
    app.run(host="0.0.0.0", port=PORT)
