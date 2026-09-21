/* دليل النشر — نظام DMS : سلوك الصفحة */
(function () {
  "use strict";

  var LS = {
    get: function (k, d) { try { var v = localStorage.getItem(k); return v === null ? d : v; } catch (e) { return d; } },
    set: function (k, v) { try { localStorage.setItem(k, v); } catch (e) {} },
    del: function (k) { try { localStorage.removeItem(k); } catch (e) {} }
  };
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };

  /* ── 1) السِّمة ─────────────────────────────────────────────── */
  var themeBtn = $("#theme");
  function applyTheme(t) {
    if (t === "light" || t === "dark") document.documentElement.setAttribute("data-theme", t);
    else document.documentElement.removeAttribute("data-theme");
    if (themeBtn) {
      themeBtn.textContent = t === "light" ? "☀" : t === "dark" ? "☾" : "◐";
      themeBtn.title = "المظهر: " + (t === "light" ? "نهاريّ" : t === "dark" ? "ليليّ" : "تلقائيّ");
    }
  }
  var theme = LS.get("dms.theme", "system");
  applyTheme(theme);
  if (themeBtn) themeBtn.addEventListener("click", function () {
    theme = theme === "system" ? "light" : theme === "light" ? "dark" : "system";
    LS.set("dms.theme", theme); applyTheme(theme);
  });

  /* ── 2) الدومين — يُكتب مرّة فيسري في كل أمرٍ في الصفحة ──────── */
  var DOM_PLACEHOLDER = "dms.<دومينك>.com";
  var domInput = $("#domain"), domApply = $("#domain-apply"), domNote = $("#domain-note");

  function setDomain(host) {
    host = (host || "").trim()
      .replace(/^https?:\/\//i, "").replace(/\/+$/, "").replace(/\s+/g, "");
    var full = host || DOM_PLACEHOLDER;
    var root = host ? host.split(".").slice(1).join(".") || host : "<دومينك>";
    $$("[data-dom]").forEach(function (el) {
      el.textContent = el.getAttribute("data-dom") === "root" ? root : full;
      el.classList.toggle("dom", !host);
    });
    if (domNote) {
      domNote.textContent = host
        ? "✔ كُتب في " + $$("[data-dom]").length + " موضعاً — والأوامر أدناه صارت جاهزةً للنسخ."
        : "لم يُضبط بعد، فالعنوان يظهر كقالب. اكتبه مرّةً ليسري في كل أمرٍ وكل رابطٍ في الصفحة.";
    }
    LS.set("dms.domain", host);
  }
  var savedDomain = LS.get("dms.domain", "");
  if (domInput) domInput.value = savedDomain;
  setDomain(savedDomain);
  if (domApply) domApply.addEventListener("click", function () { setDomain(domInput.value); });
  if (domInput) {
    domInput.addEventListener("keydown", function (e) { if (e.key === "Enter") { e.preventDefault(); setDomain(domInput.value); } });
    domInput.addEventListener("input", function () { setDomain(domInput.value); });
  }

  /* ── 3) قوائم التحقق — تُحفظ في المتصفّح ─────────────────────── */
  var boxes = $$(".checklist input[type=checkbox]");
  var meterVal = $("#meter-val"), meterBar = $("#meter-bar"), meterReset = $("#meter-reset");

  function refreshPills() {
    $$(".checklist").forEach(function (list) {
      var pill = list.previousElementSibling && list.previousElementSibling.querySelector(".pill");
      if (!pill) return;
      var all = $$("input[type=checkbox]", list);
      var done = all.filter(function (b) { return b.checked; }).length;
      pill.textContent = done + " / " + all.length;
      pill.classList.toggle("full", all.length > 0 && done === all.length);
    });
  }
  function refreshMeter() {
    var done = boxes.filter(function (b) { return b.checked; }).length;
    var pct = boxes.length ? Math.round((done / boxes.length) * 100) : 0;
    if (meterVal) meterVal.textContent = done + " / " + boxes.length;
    if (meterBar) meterBar.style.width = pct + "%";
    refreshPills();
  }
  boxes.forEach(function (b) {
    if (LS.get("dms.ck." + b.id, "") === "1") b.checked = true;
    b.addEventListener("change", function () {
      if (b.checked) LS.set("dms.ck." + b.id, "1"); else LS.del("dms.ck." + b.id);
      refreshMeter();
    });
  });
  refreshMeter();
  if (meterReset) meterReset.addEventListener("click", function () {
    if (!confirm("مسحُ كل العلامات في قوائم التحقق؟")) return;
    boxes.forEach(function (b) { b.checked = false; LS.del("dms.ck." + b.id); });
    refreshMeter();
  });

  /* ── 4) نسخ الأوامر ─────────────────────────────────────────── */
  $$(".code .copy").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var pre = btn.closest(".code").querySelector("pre");
      var text = pre ? pre.innerText : "";
      var done = function () {
        var old = btn.textContent;
        btn.textContent = "✔ نُسخ"; btn.classList.add("done");
        setTimeout(function () { btn.textContent = old; btn.classList.remove("done"); }, 1600);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function () {});
      } else {
        var ta = document.createElement("textarea");
        ta.value = text; ta.style.position = "fixed"; ta.style.opacity = "0";
        document.body.appendChild(ta); ta.select();
        try { document.execCommand("copy"); done(); } catch (e) {}
        document.body.removeChild(ta);
      }
    });
  });

  /* ── 5) تتبّع التمرير في الرِّف ───────────────────────────────── */
  var sections = $$(".doc h2[id]");
  var tocLinks = {}, tocItems = {};
  $$(".toc a[data-for]").forEach(function (a) {
    tocLinks[a.getAttribute("data-for")] = a;
    var li = a.closest("li");
    if (li && li.parentElement && li.parentElement.classList.contains("toc")) tocItems[a.getAttribute("data-for")] = li;
  });
  var subLinks = $$(".toc .sub a[data-for]");
  var allHeads = $$(".doc h2[id], .doc h3[id]");
  var currentTop = null;

  function spy() {
    var y = window.scrollY + 130, topId = null, subId = null;
    sections.forEach(function (h) { if (h.offsetTop <= y) topId = h.id; });
    allHeads.forEach(function (h) { if (h.offsetTop <= y) subId = h.id; });

    Object.keys(tocLinks).forEach(function (id) { tocLinks[id].classList.toggle("on", id === topId); });
    subLinks.forEach(function (a) { a.classList.toggle("on", a.getAttribute("data-for") === subId); });

    if (topId !== currentTop) {
      currentTop = topId;
      Object.keys(tocItems).forEach(function (id) { tocItems[id].classList.toggle("open", id === topId); });
      var act = topId && tocLinks[topId];
      if (act && window.innerWidth > 1040) {
        var rail = $(".rail"), r = act.getBoundingClientRect(), rr = rail.getBoundingClientRect();
        if (r.top < rr.top + 40 || r.bottom > rr.bottom - 40) {
          rail.scrollTop += r.top - rr.top - rail.clientHeight / 3;
        }
      }
    }
    var tt = $("#totop"); if (tt) tt.classList.toggle("show", window.scrollY > 700);
  }
  var ticking = false;
  window.addEventListener("scroll", function () {
    if (ticking) return; ticking = true;
    requestAnimationFrame(function () { spy(); ticking = false; });
  }, { passive: true });
  spy();

  var tt = $("#totop");
  if (tt) tt.addEventListener("click", function () { window.scrollTo({ top: 0, behavior: "smooth" }); });

  /* ── 6) البحث ───────────────────────────────────────────────── */
  var q = $("#q"), doc = $(".doc");
  var blocks = $$(".doc > *").filter(function (el) { return !el.classList.contains("hero"); });
  var empty = document.createElement("p");
  empty.className = "noresult"; empty.hidden = true;
  empty.textContent = "لا نتيجة.";
  if (doc) doc.appendChild(empty);

  function clearMarks(el) {
    $$("mark.hit", el).forEach(function (m) {
      var t = document.createTextNode(m.textContent);
      m.parentNode.replaceChild(t, m);
    });
    el.normalize();
  }
  function mark(el, needle) {
    var walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, null);
    var nodes = [], n;
    while ((n = walker.nextNode())) if (n.nodeValue.toLowerCase().indexOf(needle) !== -1) nodes.push(n);
    nodes.forEach(function (node) {
      var frag = document.createDocumentFragment(), s = node.nodeValue, low = s.toLowerCase(), i = 0, p;
      while ((p = low.indexOf(needle, i)) !== -1) {
        if (p > i) frag.appendChild(document.createTextNode(s.slice(i, p)));
        var m = document.createElement("mark");
        m.className = "hit"; m.textContent = s.slice(p, p + needle.length);
        frag.appendChild(m); i = p + needle.length;
      }
      if (i < s.length) frag.appendChild(document.createTextNode(s.slice(i)));
      node.parentNode.replaceChild(frag, node);
    });
  }
  var searchTimer = null;
  function runSearch() {
    var needle = (q.value || "").trim().toLowerCase();
    var shown = 0;
    blocks.forEach(function (el) {
      clearMarks(el);
      if (!needle) { el.classList.remove("dimmed"); shown++; return; }
      var hit = el.textContent.toLowerCase().indexOf(needle) !== -1;
      el.classList.toggle("dimmed", !hit);
      if (hit) { shown++; mark(el, needle); }
    });
    empty.hidden = !(needle && shown === 0);
    empty.classList.remove("dimmed");
    if (needle) { document.querySelectorAll(".toc li").forEach(function (li) { li.classList.remove("open"); }); }
    else { currentTop = null; spy(); }
  }
  if (q) {
    q.addEventListener("input", function () {
      clearTimeout(searchTimer); searchTimer = setTimeout(runSearch, 140);
    });
    q.addEventListener("keydown", function (e) { if (e.key === "Escape") { q.value = ""; runSearch(); q.blur(); } });
    document.addEventListener("keydown", function (e) {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") { e.preventDefault(); q.focus(); q.select(); }
    });
  }

  /* ── 7) الطباعة ─────────────────────────────────────────────── */
  var pb = $("#print");
  if (pb) pb.addEventListener("click", function () { window.print(); });
})();
