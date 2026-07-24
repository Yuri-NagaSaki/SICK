/* 猫脚本 / catbash.net — shared UI helpers */
(function () {
  function copyText(text, btn) {
    navigator.clipboard.writeText(text).then(function () {
      var prev = btn.textContent;
      btn.textContent = document.documentElement.lang === "zh" ? "已复制" : "copied";
      btn.classList.add("ok");
      setTimeout(function () {
        btn.textContent = prev;
        btn.classList.remove("ok");
      }, 1400);
    }).catch(function () {});
  }

  window.copyText = copyText;

  document.querySelectorAll(".copy[data-copy]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      copyText(btn.getAttribute("data-copy"), btn);
    });
  });

  function applyLang(lang) {
    document.documentElement.lang = lang;
    document.querySelectorAll("[data-en]").forEach(function (el) {
      var v = el.getAttribute("data-" + lang);
      if (v !== null) el.innerHTML = v;
    });
    var btn = document.getElementById("langBtn");
    if (btn) btn.textContent = lang === "zh" ? "EN" : "中文";
    try {
      localStorage.setItem("catbash-lang", lang);
    } catch (e) {}
  }

  window.toggleLang = function () {
    applyLang(document.documentElement.lang === "zh" ? "en" : "zh");
  };

  (function initLang() {
    var lang = "en";
    try {
      var saved = localStorage.getItem("catbash-lang") || localStorage.getItem("sick-lang");
      if (saved) lang = saved;
      else if ((navigator.language || "").toLowerCase().startsWith("zh")) lang = "zh";
    } catch (e) {}
    if (lang !== "en") applyLang(lang);
  })();

  // In-page image preview (lightbox) — no new tab
  (function initLightbox() {
    var triggers = document.querySelectorAll("[data-lightbox]");
    if (!triggers.length) return;

    var root = document.createElement("div");
    root.className = "lb";
    root.setAttribute("role", "dialog");
    root.setAttribute("aria-modal", "true");
    root.setAttribute("aria-label", "Image preview");
    root.innerHTML =
      '<div class="lb-panel">' +
      '<button type="button" class="lb-close" aria-label="Close">&times;</button>' +
      '<img alt="" />' +
      "</div>";
    document.body.appendChild(root);

    var img = root.querySelector("img");
    var closeBtn = root.querySelector(".lb-close");
    var lastFocus = null;

    function open(src, alt) {
      lastFocus = document.activeElement;
      img.src = src;
      img.alt = alt || "";
      root.classList.add("is-open");
      document.body.classList.add("lb-open");
      closeBtn.focus();
    }

    function close() {
      root.classList.remove("is-open");
      document.body.classList.remove("lb-open");
      img.removeAttribute("src");
      if (lastFocus && lastFocus.focus) lastFocus.focus();
    }

    triggers.forEach(function (el) {
      el.addEventListener("click", function (e) {
        e.preventDefault();
        var src = el.getAttribute("href") || (el.querySelector("img") && el.querySelector("img").src);
        if (!src) return;
        var alt =
          el.getAttribute("data-alt") ||
          (el.querySelector("img") && el.querySelector("img").alt) ||
          "";
        open(src, alt);
      });
    });

    closeBtn.addEventListener("click", close);
    root.addEventListener("click", function (e) {
      if (e.target === root) close();
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && root.classList.contains("is-open")) close();
    });
  })();
})();
