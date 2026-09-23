const yearTarget = document.querySelector("[data-year]");
if (yearTarget) {
  yearTarget.textContent = new Date().getFullYear();
}

const printButton = document.querySelector("[data-print-cv]");
if (printButton) {
  printButton.addEventListener("click", () => window.print());
}
