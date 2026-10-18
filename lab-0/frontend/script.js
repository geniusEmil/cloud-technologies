// Относительный путь: работает и напрямую через Flask, и за nginx
const API_URL = "/api/tasks";

const form = document.getElementById("task-form");
const input = document.getElementById("task-input");
const list = document.getElementById("task-list");
const message = document.getElementById("message");
const instance = document.getElementById("instance");

function showMessage(text, isError) {
  message.textContent = text;
  message.className = isError ? "message error" : "message";
}

// Показываем, какой экземпляр бэкенда ответил
function updateInstance(response, data) {
  instance.textContent = response.headers.get("X-Instance-Id") || (data && data.instance_id) || "—";
}

function renderTasks(tasks) {
  list.innerHTML = "";
  if (tasks.length === 0) {
    const empty = document.createElement("li");
    empty.className = "empty";
    empty.textContent = "Задач пока нет";
    list.appendChild(empty);
    return;
  }
  for (const task of tasks) {
    const li = document.createElement("li");
    const text = document.createElement("span");
    text.textContent = task.text; // textContent защищает от HTML-инъекций
    const date = document.createElement("time");
    date.textContent = new Date(task.created_at).toLocaleString("ru-RU");
    const del = document.createElement("button");
    del.className = "delete";
    del.title = "Удалить задачу";
    del.textContent = "×";
    del.addEventListener("click", () => deleteTask(task.id));
    li.append(text, date, del);
    list.appendChild(li);
  }
}

async function loadTasks() {
  try {
    const response = await fetch(API_URL);
    const data = await response.json();
    updateInstance(response, data);
    if (!response.ok) {
      showMessage("Ошибка загрузки: " + data.error, true);
      return;
    }
    renderTasks(data.tasks);
  } catch (err) {
    showMessage("Сервер недоступен", true);
  }
}

async function deleteTask(id) {
  try {
    const response = await fetch(`${API_URL}/${id}`, { method: "DELETE" });
    const data = await response.json();
    updateInstance(response, data);
    if (!response.ok) {
      showMessage("Ошибка удаления: " + data.error, true);
      return;
    }
    showMessage("Задача удалена", false);
    await loadTasks();
  } catch (err) {
    showMessage("Сервер недоступен", true);
  }
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const text = input.value.trim();
  if (!text) {
    showMessage("Введите текст задачи", true);
    return;
  }
  try {
    const response = await fetch(API_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text }),
    });
    const data = await response.json();
    updateInstance(response, data);
    if (!response.ok) {
      showMessage("Ошибка: " + data.error, true);
      return;
    }
    input.value = "";
    showMessage("Задача добавлена", false);
    await loadTasks();
  } catch (err) {
    showMessage("Сервер недоступен", true);
  }
});

loadTasks();
