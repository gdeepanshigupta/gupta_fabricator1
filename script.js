const navToggle = document.querySelector(".nav-toggle");
const navLinks = document.querySelector(".nav-links");

if (navToggle && navLinks) {
  navToggle.addEventListener("click", () => {
    const isOpen = navLinks.classList.toggle("open");
    navToggle.setAttribute("aria-expanded", String(isOpen));
  });
}

const quoteForm = document.querySelector("#quoteForm");

if (quoteForm) {
  quoteForm.addEventListener("submit", (event) => {
    event.preventDefault();
    const note = document.querySelector("#formNote");
    if (note) {
      note.textContent = "Thanks. Your enquiry is ready to be shared with Gupta Fabricator.";
    }
    quoteForm.reset();
  });
}
