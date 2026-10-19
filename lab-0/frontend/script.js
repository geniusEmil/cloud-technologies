const API_URL = "/api/tasks";
const form = document.getElementById("task-form");
const input = document.getElementById("task-input");
const list = document.getElementById("task-list");
const message = document.getElementById("message");
const instance = document.getElementById("instance");
const count = document.getElementById("task-count");
const connection = document.getElementById("connection");
const connectionLabel = document.getElementById("connection-label");
const addButton = document.getElementById("add-task");
const addLabel = document.getElementById("add-task-label");
const reloadButton = document.getElementById("reload-tasks");
let loadVersion = 0;
let hasLoaded = false;

function showMessage(text, isError = false) {
  message.textContent = text;
  message.className = isError ? "message error" : "message";
}

function updateInstance(response, data) {
  instance.textContent = response.headers.get("X-Instance-Id") || data.instance_id || "не указан";
}

function setConnection(state) {
  connection.dataset.state = state;
  connectionLabel.textContent = state === "online" ? "Список обновлён" : "Не удалось обновить";
}

async function apiRequest(url, options = {}) {
  let response;
  try {
    response = await fetch(url, { cache: "no-store", ...options });
  } catch {
    throw new Error("Сервер не отвечает. Попробуйте ещё раз.");
  }
  if (response.status === 429) {
    throw new Error("Слишком частые запросы. Подождите немного и обновите список.");
  }
  let data;
  try {
    data = await response.json();
  } catch {
    throw new Error("Не удалось получить данные. Попробуйте ещё раз.");
  }
  updateInstance(response, data);
  if (!response.ok) {
    const errors = {
      "database unavailable": "Сервис временно недоступен. Попробуйте позже.",
      "task not found": "Эту задачу уже удалили. Обновите список.",
      "task text must not be empty": "Введите текст задачи.",
    };
    throw new Error(errors[data.error] || "Не удалось выполнить запрос. Попробуйте ещё раз.");
  }
  return data;
}

function taskCount(value) {
  const lastTwo = value % 100;
  const last = value % 10;
  const word = lastTwo >= 11 && lastTwo <= 14 ? "задач" : last === 1 ? "задача" : last >= 2 && last <= 4 ? "задачи" : "задач";
  return `${value} ${word}`;
}

function showEmpty(title, description) {
  const item = document.createElement("li");
  item.className = "empty-state";
  const heading = document.createElement("h3");
  heading.textContent = title;
  const text = document.createElement("p");
  text.textContent = description;
  item.append(heading, text);
  list.replaceChildren(item);
}

function renderTasks(tasks) {
  count.textContent = taskCount(tasks.length);
  list.replaceChildren();
  if (tasks.length === 0) {
    showEmpty("Пока нет задач", "Добавьте первую задачу через форму, чтобы она появилась в общем списке.");
    return;
  }
  for (const task of tasks) {
    const item = document.createElement("li");
    item.className = "task-row";
    const content = document.createElement("div");
    content.className = "task-content";
    const text = document.createElement("p");
    text.className = "task-text";
    text.textContent = task.text;
    const date = document.createElement("time");
    date.className = "task-date";
    date.dateTime = task.created_at;
    date.textContent = "Добавлено " + new Date(task.created_at).toLocaleString("ru-RU", {
      day: "numeric", month: "short", hour: "2-digit", minute: "2-digit",
    });
    content.append(text, date);
    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "task-delete";
    remove.title = "Удалить задачу";
    remove.setAttribute("aria-label", `Удалить задачу «${task.text.slice(0, 80)}»`);
    remove.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v5M14 11v5"/></svg>';
    remove.addEventListener("click", () => deleteTask(task.id, remove));
    item.append(content, remove);
    list.appendChild(item);
  }
}

async function loadTasks() {
  const version = ++loadVersion;
  list.setAttribute("aria-busy", "true");
  reloadButton.disabled = true;
  try {
    const data = await apiRequest(API_URL);
    if (version !== loadVersion) return;
    renderTasks(data.tasks);
    hasLoaded = true;
    setConnection("online");
  } catch (error) {
    if (version !== loadVersion) return;
    setConnection("error");
    showMessage(error.message, true);
    if (!hasLoaded) showEmpty("Список не загрузился", "Проверьте подключение и нажмите «Обновить».");
  } finally {
    if (version === loadVersion) {
      list.setAttribute("aria-busy", "false");
      reloadButton.disabled = false;
    }
  }
}

async function deleteTask(id, button) {
  const position = [...list.querySelectorAll(".task-delete")].indexOf(button);
  const hadFocus = document.activeElement === button;
  button.disabled = true;
  try {
    await apiRequest(`${API_URL}/${id}`, { method: "DELETE" });
    showMessage("Задача удалена");
    await loadTasks();
    if (hadFocus && document.activeElement === document.body) {
      const buttons = list.querySelectorAll(".task-delete");
      const target = buttons[Math.min(position, buttons.length - 1)] || input;
      target.focus();
    }
  } catch (error) {
    showMessage(error.message, true);
    button.disabled = false;
  }
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (addButton.disabled) return;
  const text = input.value.trim();
  if (!text) {
    showMessage("Введите текст задачи", true);
    input.focus();
    return;
  }
  addButton.disabled = true;
  input.readOnly = true;
  addLabel.textContent = "Сохраняем…";
  try {
    await apiRequest(API_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text }),
    });
    input.value = "";
    showMessage("Задача добавлена");
    await loadTasks();
  } catch (error) {
    showMessage(error.message, true);
  } finally {
    addButton.disabled = false;
    input.readOnly = false;
    addLabel.textContent = "Добавить задачу";
    input.focus();
  }
});

reloadButton.addEventListener("click", () => {
  showMessage("");
  loadTasks();
});

// Эти разделы существуют при запуске через nginx в лабораторной 1.
async function showLabNavigation() {
  try {
    const response = await fetch("/docs/", { method: "HEAD", cache: "no-store" });
    if (response.ok) {
      document.querySelectorAll("[data-lab-page]").forEach((link) => { link.hidden = false; });
    }
  } catch {
    // Список задач работает и при самостоятельном запуске Flask.
  }
}

showLabNavigation();
loadTasks();
