const loginSection = document.querySelector("#adminLogin");
const dashboard = document.querySelector("#adminDashboard");
const loginForm = document.querySelector("#adminLoginForm");
const loginNote = document.querySelector("#adminLoginNote");
const adminStatus = document.querySelector("#adminStatus");
const recordsTable = document.querySelector("#recordsTable");
const recordSearch = document.querySelector("#recordSearch");
const exportButton = document.querySelector("#exportRecords");

const state = {
  username: sessionStorage.getItem("gfAdminUser") || "admin",
  password: sessionStorage.getItem("gfAdminPassword") || "",
  tab: "enquiries",
  records: [],
};

const statusOptions = {
  enquiries: ["new", "contacted", "quoted", "won", "closed"],
  orders: ["new", "confirmed", "in_progress", "completed", "cancelled"],
};

function escapeHtml(value) {
  return String(value == null ? "" : value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function setNote(element, message, isError = false) {
  if (!element) return;
  element.textContent = message;
  element.classList.toggle("error", isError);
}

function authHeaders() {
  return {
    Authorization: `Basic ${btoa(`${state.username}:${state.password}`)}`,
  };
}

async function adminFetch(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: {
      ...authHeaders(),
      ...(options.headers || {}),
    },
  });

  const contentType = response.headers.get("content-type") || "";
  const data = contentType.includes("application/json") ? await response.json() : await response.text();

  if (!response.ok || data.ok === false) {
    throw new Error(data.message || "Admin request failed.");
  }

  return data;
}

function formatDate(value) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString("en-IN", {
    dateStyle: "medium",
    timeStyle: "short",
  });
}

function updateSummary(summary) {
  document.querySelector("#totalEnquiries").textContent = summary.totalEnquiries || 0;
  document.querySelector("#openEnquiries").textContent = summary.openEnquiries || 0;
  document.querySelector("#totalOrders").textContent = summary.totalOrders || 0;
  document.querySelector("#openOrders").textContent = summary.openOrders || 0;
}

function filteredRecords() {
  const query = (recordSearch?.value || "").trim().toLowerCase();
  if (!query) return state.records;
  return state.records.filter((record) => JSON.stringify(record).toLowerCase().includes(query));
}

function statusSelect(record) {
  const options = statusOptions[state.tab]
    .map((status) => `<option value="${status}" ${record.status === status ? "selected" : ""}>${status.replace(/_/g, " ")}</option>`)
    .join("");
  return `<select class="status-select" data-record-id="${escapeHtml(record.id)}">${options}</select>`;
}

function renderRecords() {
  const records = filteredRecords();

  if (!records.length) {
    recordsTable.innerHTML = `<div class="empty-state">No ${state.tab === "orders" ? "service orders" : "enquiries"} found.</div>`;
    return;
  }

  if (state.tab === "orders") {
    recordsTable.innerHTML = `
      <table class="admin-table">
        <thead>
          <tr>
            <th>Date</th>
            <th>Status</th>
            <th>Service</th>
            <th>Customer</th>
            <th>Address</th>
            <th>Details</th>
          </tr>
        </thead>
        <tbody>
          ${records.map((record) => `
            <tr>
              <td>${escapeHtml(formatDate(record.createdAt))}</td>
              <td>${statusSelect(record)}</td>
              <td><strong>${escapeHtml(record.serviceName)}</strong><small>${escapeHtml(record.startingPrice)}</small></td>
              <td>${escapeHtml(record.name)}<small>${escapeHtml(record.phone)}${record.email ? ` | ${escapeHtml(record.email)}` : ""}</small></td>
              <td>${escapeHtml(record.address)}</td>
              <td>
                <small>Size: ${escapeHtml(record.size || "Not given")}</small>
                <small>Finish: ${escapeHtml(record.finish || "Not given")}</small>
                <small>Date: ${escapeHtml(record.preferredDate || "Not given")}</small>
                <span>${escapeHtml(record.notes || "")}</span>
              </td>
            </tr>
          `).join("")}
        </tbody>
      </table>
    `;
  } else {
    recordsTable.innerHTML = `
      <table class="admin-table">
        <thead>
          <tr>
            <th>Date</th>
            <th>Status</th>
            <th>Project</th>
            <th>Customer</th>
            <th>Message</th>
            <th>Source</th>
          </tr>
        </thead>
        <tbody>
          ${records.map((record) => `
            <tr>
              <td>${escapeHtml(formatDate(record.createdAt))}</td>
              <td>${statusSelect(record)}</td>
              <td><strong>${escapeHtml(record.project)}</strong></td>
              <td>${escapeHtml(record.name)}<small>${escapeHtml(record.phone)}${record.email ? ` | ${escapeHtml(record.email)}` : ""}</small></td>
              <td>${escapeHtml(record.message || "")}</td>
              <td>${escapeHtml(record.source || "")}</td>
            </tr>
          `).join("")}
        </tbody>
      </table>
    `;
  }
}

async function loadRecords() {
  setNote(adminStatus, "Loading records...");
  const data = await adminFetch(`/api/admin/${state.tab}`);
  state.records = data.records || [];
  updateSummary(data.summary || {});
  renderRecords();
  setNote(adminStatus, `Loaded ${state.records.length} ${state.tab}.`);
}

async function tryLogin(username, password) {
  state.username = username;
  state.password = password;
  await adminFetch("/api/admin/summary");
  sessionStorage.setItem("gfAdminUser", username);
  sessionStorage.setItem("gfAdminPassword", password);
  loginSection.hidden = true;
  dashboard.hidden = false;
  await loadRecords();
}

loginForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  const formData = new FormData(loginForm);
  setNote(loginNote, "Checking login...");

  try {
    await tryLogin(String(formData.get("username") || "admin"), String(formData.get("password") || ""));
    setNote(loginNote, "");
  } catch (error) {
    setNote(loginNote, "Login failed. Check the admin password.", true);
  }
});

document.querySelectorAll("[data-admin-tab]").forEach((button) => {
  button.addEventListener("click", async () => {
    document.querySelectorAll("[data-admin-tab]").forEach((item) => item.classList.remove("active"));
    button.classList.add("active");
    state.tab = button.dataset.adminTab;
    recordSearch.value = "";
    await loadRecords().catch((error) => setNote(adminStatus, error.message, true));
  });
});

recordsTable?.addEventListener("change", async (event) => {
  const select = event.target.closest(".status-select");
  if (!select) return;

  try {
    setNote(adminStatus, "Updating status...");
    await adminFetch(`/api/admin/${state.tab}/${select.dataset.recordId}/status`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: select.value }),
    });
    setNote(adminStatus, "Status updated.");
    await loadRecords();
  } catch (error) {
    setNote(adminStatus, error.message, true);
  }
});

recordSearch?.addEventListener("input", renderRecords);

document.querySelector("#refreshAdmin")?.addEventListener("click", () => {
  loadRecords().catch((error) => setNote(adminStatus, error.message, true));
});

document.querySelector("#logoutAdmin")?.addEventListener("click", () => {
  sessionStorage.removeItem("gfAdminUser");
  sessionStorage.removeItem("gfAdminPassword");
  state.password = "";
  dashboard.hidden = true;
  loginSection.hidden = false;
});

exportButton?.addEventListener("click", async () => {
  try {
    setNote(adminStatus, "Preparing CSV export...");
    const response = await fetch(`/api/export/${state.tab}.csv`, { headers: authHeaders() });
    if (!response.ok) throw new Error("Could not export CSV.");
    const blob = await response.blob();
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `${state.tab}-${new Date().toISOString().slice(0, 10)}.csv`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
    setNote(adminStatus, "CSV export downloaded.");
  } catch (error) {
    setNote(adminStatus, error.message, true);
  }
});

if (state.password) {
  tryLogin(state.username, state.password).catch(() => {
    sessionStorage.removeItem("gfAdminPassword");
  });
}
