const navToggle = document.querySelector(".nav-toggle");
const navLinks = document.querySelector(".nav-links");

if (navToggle && navLinks) {
  navToggle.addEventListener("click", () => {
    const isOpen = navLinks.classList.toggle("open");
    navToggle.setAttribute("aria-expanded", String(isOpen));
  });
}

function formToObject(form) {
  return Object.fromEntries(new FormData(form).entries());
}

function setFormNote(element, message, isError = false) {
  if (!element) return;
  element.textContent = message;
  element.classList.toggle("error", isError);
}

async function postJson(url, payload) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok || data.ok === false) {
    const details = Array.isArray(data.details) ? ` ${data.details.join(" ")}` : "";
    throw new Error(`${data.message || "Request failed."}${details}`);
  }

  return data;
}

const quoteForm = document.querySelector("#quoteForm");

if (quoteForm) {
  quoteForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const note = document.querySelector("#formNote");
    setFormNote(note, "Saving your enquiry...");

    try {
      await postJson("/api/enquiries", {
        ...formToObject(quoteForm),
        source: "contact-page",
      });
      setFormNote(note, "Thanks. Your enquiry has been saved. We will contact you soon.");
      quoteForm.reset();
    } catch (error) {
      setFormNote(note, error.message || "Could not save enquiry. Please call us directly.", true);
    }
  });
}

const serviceModal = document.querySelector("#serviceModal");
const serviceOrderForm = document.querySelector("#serviceOrderForm");
const serviceModalTitle = document.querySelector("#serviceModalTitle");
const serviceIdInput = document.querySelector("#serviceId");
const serviceNameInput = document.querySelector("#serviceName");
const serviceOrderNote = document.querySelector("#serviceOrderNote");

function openServiceModal(button) {
  if (!serviceModal || !serviceOrderForm) return;
  const serviceId = button.dataset.serviceId || "";
  const serviceName = button.dataset.serviceName || "Selected Service";
  serviceIdInput.value = serviceId;
  serviceNameInput.value = serviceName;
  serviceModalTitle.textContent = `Buy ${serviceName}`;
  setFormNote(serviceOrderNote, "");
  serviceModal.hidden = false;
  document.body.classList.add("modal-open");
  serviceOrderForm.querySelector("input[name='name']").focus();
}

function closeServiceModal() {
  if (!serviceModal) return;
  serviceModal.hidden = true;
  document.body.classList.remove("modal-open");
}

document.querySelectorAll("[data-buy-service]").forEach((button) => {
  button.addEventListener("click", () => openServiceModal(button));
});

document.querySelectorAll("[data-close-modal]").forEach((button) => {
  button.addEventListener("click", closeServiceModal);
});

if (serviceModal) {
  serviceModal.addEventListener("click", (event) => {
    if (event.target === serviceModal) closeServiceModal();
  });
}

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") closeServiceModal();
});

if (serviceOrderForm) {
  serviceOrderForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    setFormNote(serviceOrderNote, "Saving your service request...");

    try {
      await postJson("/api/orders", formToObject(serviceOrderForm));
      setFormNote(serviceOrderNote, "Your service request has been saved in the backend.");
      serviceOrderForm.reset();
      window.setTimeout(closeServiceModal, 1000);
    } catch (error) {
      setFormNote(serviceOrderNote, error.message || "Could not save service request.", true);
    }
  });
}
