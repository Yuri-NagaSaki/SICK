/*! catbash.net terminal replay — renders recorded script output (ANSI/VT100)
 *  into HTML and replays it. No dependencies; also loaded by
 *  tools/demos/render.mjs (Node) to build the static no-JS fallbacks.
 *
 *  Stream format: what a script wrote to its pty, plus two private OSC
 *  sequences that real terminals ignore (see tools/demos/pack.py):
 *    ESC]999;t BEL … ESC]999;/t BEL   typed at keyboard speed
 *    ESC]999;w=MS BEL                 pause MS milliseconds
 *  Understood: SGR (16/256/truecolor fg+bg, bold, dim, italic, underline,
 *  inverse), CR/LF/BS/TAB, CSI A B C D E F G H f J K d s u, ESC 7/8, wide
 *  (CJK) glyphs. ESC[2J keeps earlier lines as scrollback, like most
 *  terminal emulators do.
 */
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.CatTerm = api;
})(this, function () {
  "use strict";

  // Colours with a CSS class in site.css (.fN / .kN); the rest are inlined.
  var NAMED = {};
  "0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 73 80 81 114 117 180 203 214 221 222 245 250 252"
    .split(" ").forEach(function (n) { NAMED[n] = 1; });

  function hex2(n) { return (n < 16 ? "0" : "") + n.toString(16); }
  function xterm(n) {
    if (n < 16) return null;
    if (n >= 232) { var g = 8 + (n - 232) * 10; return "#" + hex2(g) + hex2(g) + hex2(g); }
    n -= 16;
    var lv = [0, 95, 135, 175, 215, 255];
    return "#" + hex2(lv[Math.floor(n / 36)]) + hex2(lv[Math.floor(n / 6) % 6]) + hex2(lv[n % 6]);
  }

  function isWide(c) {
    return (c >= 0x1100 && c <= 0x115f) || (c >= 0x2e80 && c <= 0x303e) || (c >= 0x3041 && c <= 0x33ff) ||
      (c >= 0x3400 && c <= 0x4dbf) || (c >= 0x4e00 && c <= 0x9fff) || (c >= 0xa000 && c <= 0xa4cf) ||
      (c >= 0xac00 && c <= 0xd7a3) || (c >= 0xf900 && c <= 0xfaff) || (c >= 0xfe30 && c <= 0xfe4f) ||
      (c >= 0xff00 && c <= 0xff60) || (c >= 0xffe0 && c <= 0xffe6) || (c >= 0x1f300 && c <= 0x1f64f) ||
      (c >= 0x1f900 && c <= 0x1f9ff) || (c >= 0x20000 && c <= 0x3fffd);
  }
  // Glyphs many monospace fonts lack: pin them to one cell so columns stay put.
  function isOdd(c) {
    return (c >= 0x2800 && c <= 0x28ff) || (c >= 0x2580 && c <= 0x259f) || (c >= 0x25a0 && c <= 0x25ff) ||
      (c >= 0x2600 && c <= 0x27bf) || c === 0x2139;
  }

  // ---------- tokenizer ----------
  // ops: [0,text] [1] CR [2] LF [3] BS [4] TAB [5,final,params,priv] CSI
  //      [6,ms] wait [7] type-on [8] type-off [9] ESC7 [10] ESC8
  function parse(s) {
    var ops = [], i = 0, n = s.length, start = 0;
    function flush(j) { if (j > start) ops.push([0, s.slice(start, j)]); }
    while (i < n) {
      var ch = s.charCodeAt(i);
      if (ch >= 32 && ch !== 127) { i++; continue; }
      flush(i);
      if (ch === 13) ops.push([1]);
      else if (ch === 10) ops.push([2]);
      else if (ch === 8) ops.push([3]);
      else if (ch === 9) ops.push([4]);
      else if (ch === 27) {
        var nx = s.charAt(i + 1);
        if (nx === "[") {
          var j = i + 2, priv = "";
          if (/[?>=<!]/.test(s.charAt(j))) priv = s.charAt(j++);
          var p0 = j;
          while (j < n && /[0-9;:]/.test(s.charAt(j))) j++;
          while (j < n && /[ -\/]/.test(s.charAt(j))) j++; // intermediates
          if (j < n) ops.push([5, s.charAt(j), s.slice(p0, j), priv]);
          i = j + 1; start = i; continue;
        }
        if (nx === "]") {
          var e = i + 2, body;
          while (e < n && s.charCodeAt(e) !== 7 && !(s.charCodeAt(e) === 27 && s.charAt(e + 1) === "\\")) e++;
          body = s.slice(i + 2, e);
          i = e + (s.charCodeAt(e) === 7 ? 1 : 2); start = i;
          if (body === "999;t") ops.push([7]);
          else if (body === "999;/t") ops.push([8]);
          else if (body.indexOf("999;w=") === 0) ops.push([6, parseInt(body.slice(6), 10) || 0]);
          continue;
        }
        if (nx === "7") ops.push([9]);
        else if (nx === "8") ops.push([10]);
        else if (nx === "(" || nx === ")") i++; // charset designation: skip one more
        i += 2; start = i; continue;
      }
      i++; start = i; // other C0 controls (BEL …) are ignored
    }
    flush(n);
    return ops;
  }

  // ---------- screen ----------
  var PLAIN = { fg: null, bg: null, b: 0, d: 0, it: 0, u: 0, inv: 0 };

  function Screen(rows) {
    this.rows = rows || 40;
    this.reset();
  }
  Screen.prototype.reset = function () {
    this.lines = [[]];
    this.row = 0; this.col = 0; this.top = 0;
    this.st = PLAIN; this.saved = null;
    this.dirty = {};
    this.dirty[0] = 1;
  };
  Screen.prototype.line = function (r) {
    while (this.lines.length <= r) { this.lines.push([]); this.dirty[this.lines.length - 1] = 1; }
    this.dirty[r] = 1;
    return this.lines[r];
  };
  Screen.prototype.put = function (text) {
    for (var k = 0; k < text.length; k++) {
      var cp = text.codePointAt(k);
      if (cp > 0xffff) k++;
      if (cp >= 0x300 && cp <= 0x36f) continue; // combining marks: drop
      var ch = String.fromCodePoint(cp), w = isWide(cp) ? 2 : 1;
      var L = this.line(this.row);
      while (L.length < this.col) L.push([" ", PLAIN, 1]);
      if (L[this.col] && L[this.col][2] === 0 && this.col > 0) L[this.col - 1] = [" ", PLAIN, 1]; // split a wide glyph
      L[this.col] = [ch, this.st, w];
      if (w === 2) {
        if (L[this.col + 1] && L[this.col + 1][2] === 2 && L[this.col + 2]) L[this.col + 2] = [" ", PLAIN, 1];
        L[this.col + 1] = ["", this.st, 0];
      }
      this.col += w;
    }
  };
  Screen.prototype.lf = function () {
    this.row++;
    this.line(this.row);
    if (this.row - this.top >= this.rows) this.top = this.row - this.rows + 1;
  };
  Screen.prototype.eraseLine = function (mode) {
    var L = this.line(this.row);
    if (mode === 2) L.length = 0;
    else if (mode === 1) { for (var c = 0; c <= this.col && c < L.length; c++) L[c] = [" ", PLAIN, 1]; }
    else if (L.length > this.col) L.length = this.col;
  };
  Screen.prototype.sgr = function (params) {
    var p = params === "" ? [0] : params.split(/[;:]/).map(function (x) { return parseInt(x, 10) || 0; });
    var s = {}; for (var k in this.st) s[k] = this.st[k];
    for (var i = 0; i < p.length; i++) {
      var v = p[i];
      if (v === 0) s = { fg: null, bg: null, b: 0, d: 0, it: 0, u: 0, inv: 0 };
      else if (v === 1) s.b = 1;
      else if (v === 2) s.d = 1;
      else if (v === 3) s.it = 1;
      else if (v === 4) s.u = 1;
      else if (v === 7) s.inv = 1;
      else if (v === 22) { s.b = 0; s.d = 0; }
      else if (v === 23) s.it = 0;
      else if (v === 24) s.u = 0;
      else if (v === 27) s.inv = 0;
      else if (v >= 30 && v <= 37) s.fg = v - 30;
      else if (v >= 90 && v <= 97) s.fg = v - 82;
      else if (v === 39) s.fg = null;
      else if (v >= 40 && v <= 47) s.bg = v - 40;
      else if (v >= 100 && v <= 107) s.bg = v - 92;
      else if (v === 49) s.bg = null;
      else if (v === 38 || v === 48) {
        var key = v === 38 ? "fg" : "bg";
        if (p[i + 1] === 5) { s[key] = p[i + 2] & 255; i += 2; }
        else if (p[i + 1] === 2) { s[key] = "#" + hex2(p[i + 2] & 255) + hex2(p[i + 3] & 255) + hex2(p[i + 4] & 255); i += 4; }
      }
    }
    this.st = s;
  };
  Screen.prototype.csi = function (f, params, priv) {
    if (priv) return; // ?25l cursor hide etc.
    var a = params.split(";"), n = parseInt(a[0], 10) || 0, m = Math.max(1, n);
    switch (f) {
      case "m": this.sgr(params); break;
      case "K": this.eraseLine(n); break;
      case "J":
        if (n === 2 || n === 3) { // clear screen: keep history above, start a fresh page
          var last = this.lines[this.lines.length - 1];
          this.top = (last && last.length === 0) ? this.lines.length - 1 : this.lines.length;
          this.row = this.top; this.col = 0; this.line(this.row);
        } else if (n === 0) {
          this.eraseLine(0);
          for (var r = this.row + 1; r < this.lines.length; r++) this.dirty[r] = 1;
          this.lines.length = this.row + 1;
        }
        break;
      case "A": this.row = Math.max(this.top, this.row - m); break;
      case "B": this.row += m; this.line(this.row); break;
      case "C": this.col += m; break;
      case "D": this.col = Math.max(0, this.col - m); break;
      case "E": this.row += m; this.col = 0; this.line(this.row); break;
      case "F": this.row = Math.max(this.top, this.row - m); this.col = 0; break;
      case "G": this.col = m - 1; break;
      case "d": this.row = this.top + m - 1; this.line(this.row); break;
      case "H": case "f":
        this.row = this.top + Math.max(1, n) - 1;
        this.col = Math.max(1, parseInt(a[1], 10) || 1) - 1;
        this.line(this.row);
        break;
      case "s": this.saved = [this.row, this.col]; break;
      case "u": if (this.saved) { this.row = this.saved[0]; this.col = this.saved[1]; } break;
    }
  };
  // Apply one op; returns a pacing hint for the player.
  Screen.prototype.apply = function (op) {
    switch (op[0]) {
      case 0: this.put(op[1]); break;
      case 1: this.col = 0; break;
      case 2: this.lf(); this.col = 0; return "lf"; // ONLCR streams always carry CR first
      case 3: this.col = Math.max(0, this.col - 1); break;
      case 4: this.col = (Math.floor(this.col / 8) + 1) * 8; break;
      case 5: this.csi(op[1], op[2], op[3]); break;
      case 9: this.saved = [this.row, this.col, this.st]; break;
      case 10: if (this.saved) { this.row = this.saved[0]; this.col = this.saved[1]; if (this.saved[2]) this.st = this.saved[2]; } break;
    }
    return "";
  };

  // ---------- HTML ----------
  function esc(c) { return c === "<" ? "&lt;" : c === ">" ? "&gt;" : c === "&" ? "&amp;" : c; }

  function styleAttr(st) {
    var fg = st.fg, bg = st.bg, cls = [], css = [];
    if (st.inv) { var t = fg; fg = bg === null ? "bgx" : bg; bg = t === null ? "fgx" : t; }
    function color(v, pre, prop) {
      if (v === null) return;
      if (v === "bgx" || v === "fgx") { cls.push(pre + v.slice(0, 2)); return; }
      if (typeof v === "number" && NAMED[v]) cls.push(pre + v);
      else css.push(prop + ":" + (typeof v === "number" ? xterm(v) : v));
    }
    color(fg, "f", "color");
    color(bg, "k", "background");
    if (st.b) cls.push("b");
    if (st.d) cls.push("d");
    if (st.it) cls.push("i");
    if (st.u) cls.push("u");
    var out = "";
    if (cls.length) out += ' class="' + cls.join(" ") + '"';
    if (css.length) out += ' style="' + css.join(";") + '"';
    return out;
  }

  // cur = column of the cursor on this line (or -1)
  function lineHTML(L, cur) {
    var end = L.length;
    while (end > 0 && L[end - 1][0] === " " && L[end - 1][1].bg === null && !L[end - 1][1].inv && L[end - 1][1].u !== 1) end--;
    var html = "", runSt = null, run = "";
    function close() {
      if (run) html += runSt === PLAIN || (runSt && styleAttr(runSt) === "") ? run : "<span" + styleAttr(runSt) + ">" + run + "</span>";
      run = "";
    }
    var lim = Math.max(end, cur + 1);
    for (var c = 0; c < lim; c++) {
      var cell = L[c] || [" ", PLAIN, 1];
      if (cell[2] === 0) continue;
      var ch = cell[0], cp = ch.codePointAt(0), piece;
      if (cell[2] === 2) piece = '<i class="w">' + esc(ch) + "</i>";
      else if (isOdd(cp)) piece = '<i class="g">' + esc(ch) + "</i>";
      else piece = esc(ch);
      if (c === cur) { close(); html += '<span class="cur">' + piece + "</span>"; runSt = null; continue; }
      if (cell[1] !== runSt) { close(); runSt = cell[1]; }
      run += piece;
    }
    close();
    return html;
  }

  function render(text, rows) {
    var sc = new Screen(rows), ops = parse(text);
    for (var i = 0; i < ops.length; i++) sc.apply(ops[i]);
    return sc;
  }

  function screenHTML(sc, withCursor) {
    var out = [];
    for (var r = 0; r < sc.lines.length; r++) out.push(lineHTML(sc.lines[r], withCursor && r === sc.row ? sc.col : -1));
    while (out.length > 1 && out[out.length - 1] === "" && sc.row < out.length - 1) out.pop();
    return '<span class="ln">' + out.join('</span><span class="ln">') + "</span>";
  }

  return { parse: parse, Screen: Screen, render: render, screenHTML: screenHTML, lineHTML: lineHTML };
});

// ---------- browser player ----------
(function () {
  if (typeof document === "undefined") return;
  var T = window.CatTerm;
  var reduce = window.matchMedia && matchMedia("(prefers-reduced-motion: reduce)").matches;
  var cache = {};

  function load(src) {
    if (!cache[src]) {
      cache[src] = fetch(src, { cache: "no-cache" }).then(function (r) {
        if (!r.ok) throw new Error(r.status);
        return r.text();
      });
      cache[src].catch(function () { delete cache[src]; });
    }
    return cache[src];
  }

  function lang() { return (document.documentElement.lang || "en").slice(0, 2); }

  function Player(fig) {
    var self = this;
    this.fig = fig;
    this.out = fig.querySelector(".term-screen");
    this.btnPlay = fig.querySelector("[data-act=play]");
    this.btnReplay = fig.querySelector("[data-act=replay]");
    this.staticHTML = this.out.innerHTML;
    this.staticSrc = fig.getAttribute("data-src");
    this.state = "idle"; // idle | playing | paused | done
    this.timer = 0;
    this.stick = true;
    this.lineEls = [];
    this.gen = 0;
    this.out.addEventListener("scroll", function () {
      var o = self.out;
      self.stick = o.scrollHeight - o.scrollTop - o.clientHeight < 28;
    }, { passive: true });
    if (this.btnPlay) this.btnPlay.addEventListener("click", function () { self.toggle(); });
    if (this.btnReplay) this.btnReplay.addEventListener("click", function () { self.start(true); });
    this.syncButtons();
  }

  Player.prototype.src = function () {
    var f = this.fig;
    return (lang() === "zh" && f.getAttribute("data-src-zh")) || f.getAttribute("data-src");
  };

  Player.prototype.setSource = function (src, srcZh) {
    this.fig.setAttribute("data-src", src);
    if (srcZh) this.fig.setAttribute("data-src-zh", srcZh); else this.fig.removeAttribute("data-src-zh");
    // A new demo was picked: play it (or jump to its last frame without motion).
    if (reduce) this.showFinal(); else this.start(true);
  };

  // Language or source changed: replay if motion is fine, else jump to the end.
  Player.prototype.refresh = function () {
    if (this.state === "idle" && !this.seen) return;
    if (reduce || this.state === "done") this.showFinal(); else this.start(true);
  };

  Player.prototype.mount = function () {
    this.out.innerHTML = "";
    this.lineEls = [];
    this.out.scrollTop = 0;
    this.stick = true;
  };

  Player.prototype.paint = function (sc, cursor) {
    var d = sc.dirty, r;
    for (var k in d) {
      r = +k;
      while (this.lineEls.length <= r) {
        var el = document.createElement("span");
        el.className = "ln";
        this.out.appendChild(el);
        this.lineEls.push(el);
      }
    }
    for (r = sc.lines.length; r < this.lineEls.length; r++) this.lineEls[r].innerHTML = "";
    if (this.curRow !== undefined && this.curRow !== sc.row && this.lineEls[this.curRow]) d[this.curRow] = 1;
    for (k in d) {
      r = +k;
      if (r < sc.lines.length) this.lineEls[r].innerHTML = T.lineHTML(sc.lines[r], cursor && r === sc.row ? sc.col : -1);
    }
    this.curRow = cursor ? sc.row : undefined;
    sc.dirty = {};
    if (this.stick) this.out.scrollTop = this.out.scrollHeight;
  };

  Player.prototype.showFinal = function () {
    var self = this, gen = ++this.gen, src = this.src();
    clearTimeout(this.timer);
    if (src === this.staticSrc) {
      this.out.innerHTML = this.staticHTML;
      this.state = "done"; this.syncButtons();
      return;
    }
    load(src).then(function (text) {
      if (gen !== self.gen) return;
      var sc = T.render(text, 40);
      self.mount();
      self.out.innerHTML = T.screenHTML(sc, true);
      self.state = "done"; self.syncButtons();
    }).catch(function () {});
  };

  Player.prototype.start = function (force) {
    var self = this, gen = ++this.gen;
    clearTimeout(this.timer);
    this.seen = true;
    if (reduce && !force) { this.showFinal(); return; }
    this.fig.classList.add("is-busy");
    this.state = "loading";
    this.syncButtons();
    load(this.src()).then(function (text) {
      if (gen !== self.gen) return;
      self.fig.classList.remove("is-busy");
      self.ops = T.parse(text);
      self.sc = new T.Screen(40);
      self.i = 0;
      self.typing = false;
      self.mount();
      self.state = "playing";
      self.syncButtons();
      self.step(gen);
    }).catch(function () {
      if (gen !== self.gen) return;
      self.fig.classList.remove("is-busy");
      self.out.innerHTML = self.staticHTML; // keep the static frame
      self.state = "done"; self.syncButtons();
    });
  };

  // Run ops until a pacing point, paint, schedule the next step.
  Player.prototype.step = function (gen) {
    if (gen !== this.gen || this.state !== "playing") return;
    var ops = this.ops, sc = this.sc, delay = 0, lines = 0, budget = 0;
    while (this.i < ops.length && !delay) {
      var op = ops[this.i++];
      if (op[0] === 6) { delay = Math.min(op[1], 1500); break; }
      if (op[0] === 7) { this.typing = true; delay = 380; break; }
      if (op[0] === 8) { this.typing = false; delay = 420; break; }
      if (this.typing && op[0] === 0 && op[1].length > 1) {
        // type one character at a time
        ops.splice(this.i, 0, [0, op[1].slice(1)]);
        op = [0, op[1].charAt(0)];
        sc.apply(op);
        delay = 26 + Math.round(Math.random() * 34);
        break;
      }
      if (sc.apply(op) === "lf") {
        lines++;
        budget += sc.lines[sc.row - 1] && sc.lines[sc.row - 1].length > 0 ? 1 : 0.4;
        if (budget >= 1) delay = 16;
      }
    }
    this.paint(sc, true);
    if (this.i >= ops.length) { this.state = "done"; this.syncButtons(); return; }
    var self = this;
    this.timer = setTimeout(function () { self.step(gen); }, delay || 16);
  };

  Player.prototype.toggle = function () {
    if (this.state === "loading") return;
    if (this.state === "playing") {
      this.state = "paused"; clearTimeout(this.timer);
    } else if (this.state === "paused") {
      this.state = "playing"; this.step(this.gen);
    } else {
      this.start(true);
      return;
    }
    this.syncButtons();
  };

  Player.prototype.syncButtons = function () {
    var b = this.btnPlay, zh = lang() === "zh";
    this.fig.setAttribute("data-state", this.state);
    if (!b) return;
    var playing = this.state === "playing";
    b.setAttribute("aria-label", playing ? (zh ? "暂停" : "Pause") : (zh ? "播放" : "Play"));
    b.setAttribute("title", b.getAttribute("aria-label"));
    b.classList.toggle("is-playing", playing);
  };

  var players = [];
  function init() {
    var figs = document.querySelectorAll(".term[data-src]");
    var io = "IntersectionObserver" in window ? new IntersectionObserver(function (ents) {
      ents.forEach(function (e) {
        if (!e.isIntersecting) return;
        io.unobserve(e.target);
        var p = e.target._player;
        if (p && p.state === "idle") p.start(false);
      });
    }, { threshold: 0.12 }) : null;
    for (var i = 0; i < figs.length; i++) {
      var p = new Player(figs[i]);
      figs[i]._player = p;
      players.push(p);
      if (reduce) {
        // No motion: keep the static last frame (swap in the 中文 capture if needed).
        p.state = "done"; p.seen = true; p.syncButtons();
        if (p.src() !== p.staticSrc) p.showFinal();
        continue;
      }
      // Below the fold: clear the static frame now so the replay starts fresh.
      p.out.innerHTML = "";
      p.out.classList.add("live");
      if (io) io.observe(figs[i]); else p.start(false);
    }
    document.documentElement.classList.add("term-ready");
  }

  document.addEventListener("catbash:lang", function () {
    players.forEach(function (p) { p.syncButtons(); if (p.fig.getAttribute("data-src-zh")) p.refresh(); });
  });

  window.CatTermPlayers = players;
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
