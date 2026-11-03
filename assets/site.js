/* 猫脚本 / catbash.net — language, theme, copy buttons, command tabs. */
(function () {
  "use strict";
  var doc = document, root = doc.documentElement;

  function store(k, v) {
    try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) {}
    return null;
  }
  function $$(sel, el) { return Array.prototype.slice.call((el || doc).querySelectorAll(sel)); }
  function lang() { return root.lang.slice(0, 2) === "zh" ? "zh" : "en"; }

  // ---------- live region for "copied" ----------
  var live = doc.createElement("span");
  live.className = "sr-only";
  live.setAttribute("aria-live", "polite");
  doc.body.appendChild(live);

  // ---------- language ----------
  var enTitle = doc.title;
  function applyLang(l, save) {
    root.lang = l === "zh" ? "zh-CN" : "en";
    $$("[data-en]").forEach(function (el) {
      var v = el.getAttribute("data-" + l);
      if (v !== null && el.innerHTML !== v) el.innerHTML = v;
    });
    $$("[data-label-en]").forEach(function (el) {
      var v = el.getAttribute("data-label-" + l);
      if (v !== null) { el.setAttribute("aria-label", v); el.setAttribute("title", v); }
    });
    var zt = root.getAttribute("data-title-zh");
    doc.title = l === "zh" && zt ? zt : enTitle;
    var btn = doc.getElementById("langBtn");
    if (btn) {
      btn.textContent = l === "zh" ? "EN" : "中文";
      btn.setAttribute("aria-label", l === "zh" ? "Switch to English" : "切换到中文");
      btn.setAttribute("lang", l === "zh" ? "en" : "zh-CN");
    }
    if (save) store("catbash-lang", l);
    doc.dispatchEvent(new CustomEvent("catbash:lang", { detail: l }));
  }
  window.toggleLang = function () { applyLang(lang() === "zh" ? "en" : "zh", true); };
  var langBtn = doc.getElementById("langBtn");
  if (langBtn) langBtn.addEventListener("click", window.toggleLang);

  (function () {
    var l = store("catbash-lang") || store("sick-lang");
    if (l !== "zh" && l !== "en") l = /^zh\b/i.test(navigator.language || "") ? "zh" : "en";
    applyLang(l, false);
  })();

  // ---------- theme ----------
  var themeBtn = doc.getElementById("themeBtn");
  function effectiveTheme() {
    var t = root.getAttribute("data-theme");
    if (t) return t;
    return window.matchMedia && matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
  }
  function syncThemeBtn() {
    if (!themeBtn) return;
    var dark = effectiveTheme() === "dark", zh = lang() === "zh";
    var label = dark ? (zh ? "切换到浅色主题" : "Switch to light theme") : (zh ? "切换到深色主题" : "Switch to dark theme");
    themeBtn.setAttribute("aria-label", label);
    themeBtn.setAttribute("title", label);
  }
  if (themeBtn) {
    themeBtn.addEventListener("click", function () {
      var next = effectiveTheme() === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      store("catbash-theme", next);
      syncThemeBtn();
    });
    doc.addEventListener("catbash:lang", syncThemeBtn);
    syncThemeBtn();
  }

  // ---------- short-link host (ba.sh ⇄ catbash.net) ----------
  var HOSTS = ["ba.sh", "catbash.net"];
  var host = store("catbash-host");
  if (HOSTS.indexOf(host) < 0) host = "ba.sh";
  function withHost(cmd) { return host === "ba.sh" ? cmd : cmd.replace(/https:\/\/ba\.sh\//g, "https://" + host + "/"); }
  function applyHost() {
    $$("code.cmd[data-cmd]").forEach(function (c) { c.textContent = withHost(c.getAttribute("data-cmd")); });
    $$(".hostsw button").forEach(function (b) { b.setAttribute("aria-pressed", String(b.getAttribute("data-host") === host)); });
  }
  $$(".hostsw button").forEach(function (b) {
    b.addEventListener("click", function () {
      host = b.getAttribute("data-host");
      store("catbash-host", host);
      applyHost();
    });
  });
  applyHost();

  // ---------- copy ----------
  function fallbackCopy(text) {
    var ta = doc.createElement("textarea");
    ta.value = text;
    ta.setAttribute("readonly", "");
    ta.style.cssText = "position:fixed;top:0;left:0;opacity:0;pointer-events:none";
    doc.body.appendChild(ta);
    ta.select();
    ta.setSelectionRange(0, text.length);
    var ok = false;
    try { ok = doc.execCommand("copy"); } catch (e) {}
    doc.body.removeChild(ta);
    return ok;
  }
  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text).then(function () { return true; }, function () { return fallbackCopy(text); });
    }
    return Promise.resolve(fallbackCopy(text));
  }
  doc.addEventListener("click", function (e) {
    var btn = e.target.closest && e.target.closest(".copy");
    if (!btn) return;
    var text = btn.getAttribute("data-copy");
    if (!text) {
      var line = btn.closest(".cmdline");
      var code = line && line.querySelector(".cmd");
      text = code ? code.textContent : "";
    }
    if (!text) return;
    copyText(text).then(function (ok) {
      var label = btn.querySelector("span") || btn;
      var zh = lang() === "zh";
      clearTimeout(btn._t);
      if (!btn._orig) btn._orig = label.innerHTML;
      label.textContent = ok ? (zh ? "已复制" : "Copied") : (zh ? "复制失败" : "Copy failed");
      btn.classList.toggle("is-copied", ok);
      live.textContent = ok ? (zh ? "已复制到剪贴板" : "Copied to clipboard") : "";
      btn._t = setTimeout(function () {
        label.innerHTML = label.getAttribute("data-" + lang()) || btn._orig;
        btn._orig = null;
        btn.classList.remove("is-copied");
      }, 1600);
    });
  });

  // ---------- command tabs ----------
  $$("[data-tabs]").forEach(function (box) {
    var tabs = $$("[role=tab]", box);
    var code = box.querySelector("code.cmd");
    var hint = box.querySelector(".cmdbox-hint");
    var term = box.getAttribute("data-term") && doc.getElementById(box.getAttribute("data-term"));
    function select(tab, focus) {
      tabs.forEach(function (t) {
        var on = t === tab;
        t.setAttribute("aria-selected", String(on));
        t.tabIndex = on ? 0 : -1;
      });
      if (focus) tab.focus();
      code.setAttribute("data-cmd", tab.getAttribute("data-cmd"));
      code.textContent = withHost(tab.getAttribute("data-cmd"));
      if (hint) {
        hint.setAttribute("data-en", tab.getAttribute("data-hint-en") || "");
        hint.setAttribute("data-zh", tab.getAttribute("data-hint-zh") || "");
        hint.innerHTML = tab.getAttribute("data-hint-" + lang()) || "";
      }
      var demo = tab.getAttribute("data-demo");
      if (term && demo && term._player) {
        var base = "/assets/demos/" + demo;
        term._player.setSource(base + ".ansi", tab.hasAttribute("data-demo-zh") ? base + ".zh.ansi" : "");
        var title = term.querySelector(".term-title");
        if (title) title.textContent = "root@catlab-01: ~ — " + demo;
      }
    }
    tabs.forEach(function (t, i) {
      t.addEventListener("click", function () { select(t, false); });
      t.addEventListener("keydown", function (e) {
        var k = e.key, j = -1;
        if (k === "ArrowRight") j = (i + 1) % tabs.length;
        else if (k === "ArrowLeft") j = (i - 1 + tabs.length) % tabs.length;
        else if (k === "Home") j = 0;
        else if (k === "End") j = tabs.length - 1;
        if (j < 0) return;
        e.preventDefault();
        select(tabs[j], true);
      });
    });
  });
})();
