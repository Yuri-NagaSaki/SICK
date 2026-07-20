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
})();
