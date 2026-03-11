document.addEventListener("DOMContentLoaded", function () {
  var topButton = document.querySelector(".md-top");
  if (!topButton) {
    return;
  }

  var threshold = 240;

  function syncTopButton() {
    if (window.scrollY > threshold) {
      topButton.classList.add("kb-top-visible");
    } else {
      topButton.classList.remove("kb-top-visible");
    }
  }

  syncTopButton();
  window.addEventListener("scroll", syncTopButton, { passive: true });
});
