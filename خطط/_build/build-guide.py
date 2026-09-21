# -*- coding: utf-8 -*-
"""
مولِّد النسخة المرئية من دليل النشر.

    python "خطط/_build/build-guide.py"

يقرأ  :  خطط/دليل النشر الشامل — نظام DMS.md
يكتب  :  خطط/دليل النشر الشامل — نظام DMS.html   (مكتفٍ بذاته — بلا ملفاتٍ جانبية)

🔑 القاعدة: **الـMarkdown هو المصدر الوحيد.** لا يُحرَّر الـHTML بيد أبداً —
   يُعدَّل الـMarkdown ثم يُعاد تشغيل هذا الأمر.
"""

import io
import os
import re
import sys
import unicodedata

import markdown

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                       # خطط/
SRC = os.path.join(ROOT, "دليل النشر الشامل — نظام DMS.md")
OUT = os.path.join(ROOT, "دليل النشر الشامل — نظام DMS.html")
CSS = os.path.join(HERE, "guide.css")
JS = os.path.join(HERE, "guide.js")

DOMAIN_FULL = "dms.<دومينك>.com"
DOMAIN_ROOT = "<دومينك>"


# ── مرساةٌ مطابقةٌ لِما يولّده GitHub، فتبقى روابط الـMarkdown عاملةً ──────────
def slugify(text, sep="-"):
    out = []
    for ch in text.strip().lower():
        cat = unicodedata.category(ch)
        if ch in " \t":
            out.append(sep)
        elif cat[0] in "LN" or cat in ("Mn", "Mc") or ch in "-_":
            out.append(ch)
    return "".join(out)


def read(path):
    with io.open(path, "r", encoding="utf-8") as f:
        return f.read()


# ── تصنيف التنبيهات من العلامة التي يبدأ بها الاقتباس في النصّ نفسه ──────────
CALLOUT = [
    ("\U0001F534", "danger", "حرج"),              # 🔴
    ("⚠️", "warn", "انتبه"),            # ⚠️
    ("\U0001F511", "key", "قاعدة"),               # 🔑
    ("\U0001F9EA", "trial", "التجربة"),           # 🧪
    ("\U0001F504", "trial", "الانتقال"),          # 🔄
    ("✅", "ok", "تمّ"),                      # ✅
    ("\U0001F510", "danger", "أمان"),             # 🔐
    ("\U0001F195", "ok", "جديد"),                 # 🆕
    ("\U0001F4CB", "info", "ملاحظة"),             # 📋
    ("\U0001F4DD", "info", "دوّن"),                # 📝
    ("\U0001F517", "info", "رابط"),               # 🔗
    ("\U0001F680", "info", "نشر"),                # 🚀
    ("\U0001F50E", "info", "تنبّه"),               # 🔎
]

LEADING_EMOJI = re.compile(
    "^(?:<[^>]+>)*\\s*("
    "\U0001F300-\U0001FAFF"
    "|[←-⇿①-➿⬀-⯿]️?"
    ")\\s*"
)


def classify(inner_html):
    """يُعيد (صنف، وسم) لأول علامةٍ تظهر في أوّل ~120 حرفاً من الاقتباس."""
    head = re.sub(r"<[^>]+>", "", inner_html)[:120]
    for emoji, cls, tag in CALLOUT:
        if emoji in head:
            return cls, tag, emoji
    return "info", "", None


def build_callouts(html):
    """<blockquote> ⟵ تنبيهٌ مُصنَّف، مع إسقاط العلامة من النصّ وإظهارها وسماً."""
    def one(m):
        inner = m.group(1)
        cls, tag, emoji = classify(inner)
        if emoji:
            inner = inner.replace(emoji + " ", "", 1).replace(emoji, "", 1)
        label = ('<p class="tag">%s %s</p>' % (emoji, tag)) if tag else ""
        return '<div class="call %s">%s%s</div>' % (cls, label, inner)

    return re.sub(r"<blockquote>(.*?)</blockquote>", one, html, flags=re.S)


def build_code(html):
    """<pre><code> ⟵ بطاقة طرفية بترويسةٍ وزرّ نسخ."""
    n = [0]

    def one(m):
        attrs, body = m.group(1), m.group(2)
        lang = "PowerShell"
        if "language-yaml" in attrs:
            lang = "YAML"
        elif "language-bash" in attrs:
            lang = "Bash"
        elif "language-text" in attrs or not attrs.strip():
            lang = "نصّ"
        n[0] += 1
        return (
            '<div class="code">'
            '<div class="head"><span class="dot"></span><span class="lang">%s</span>'
            '<span class="grow"></span>'
            '<button type="button" class="copy">نسخ</button></div>'
            "<pre><code%s>%s</code></pre></div>" % (lang, attrs, body)
        )

    return re.sub(r"<pre><code([^>]*)>(.*?)</code></pre>", one, html, flags=re.S)


def build_checklists(html):
    """`- [ ]` ⟵ مربّعاتُ تحقّقٍ حقيقية تُحفظ حالتها، مع شارة تقدّمٍ فوق كل قائمة."""
    seq = [0]

    def item(m):
        seq[0] += 1
        checked = m.group(1).lower() == "x"
        return (
            '<li><input type="checkbox" id="ck%d"%s>'
            '<label for="ck%d">' % (seq[0], " checked" if checked else "", seq[0])
        )

    def block(m):
        inner = m.group(1)
        if "[ ]" not in inner and "[x]" not in inner and "[X]" not in inner:
            return m.group(0)
        inner = re.sub(r"<li>\s*\[([ xX])\]\s*", item, inner)
        inner = inner.replace("</li>", "</label></li>")
        count = inner.count("<input")
        return (
            '<div class="checkhead"><span class="pill">0 / %d</span></div>'
            '<ul class="checklist">%s</ul>' % (count, inner)
        )

    return re.sub(r"<ul>((?:(?!</?ul>).)*?)</ul>", block, html, flags=re.S)


def build_tables(html):
    return re.sub(r"<table>(.*?)</table>",
                  lambda m: '<div class="tablewrap"><table>%s</table></div>' % m.group(1),
                  html, flags=re.S)


STEP = re.compile(r'^(<h2 id="[^"]*">)\s*([0-9]{1,2}[ء-ي]?)\)\s*')


def build_headings(html):
    """شارةُ رقم المرحلة على h2 (الدليل تسلسلٌ حقيقيّ، فالترقيم معلومة)، والعلامة أيقونة."""
    def h2(m):
        return '%s<span class="step">%s</span>' % (m.group(1), m.group(2))

    html = re.sub(r'(<h2 id="[^"]*">)\s*([0-9]{1,2}[ء-ي]?)\)\s*', h2, html)

    def icon(m):
        return '%s<span class="hicon">%s</span> ' % (m.group(1), m.group(2))

    return re.sub(
        r'(<h[234] id="[^"]*">(?:<span class="step">[^<]*</span>)?)\s*'
        r"([\U0001F300-\U0001FAFF✅⚠️⭐]+)\s*", icon, html)


# 🔴 **مرّةٌ واحدة بتبديلٍ واحد**: كتابةُ البديل ثم البحث فيه مرّةً أخرى تلفّ ما لُفّ،
#    والنصُّ المُدرَج **يُهرَّب** — فـ`<دومينك>` الخامّ يقرؤه المتصفّح **وسماً** لا نصّاً.
DOMAIN_RE = re.compile(
    r"dms\.(?:<|&lt;)دومينك(?:>|&gt;)\.com"     # العنوان الكامل
    r"|(?:<|&lt;)دومينك(?:>|&gt;)"              # الجذر وحده
)
ESC_FULL = "dms.&lt;دومينك&gt;.com"
ESC_ROOT = "&lt;دومينك&gt;"


def wrap_domains(html):
    """كلُّ ذكرٍ للدومين يصير عنصراً حيّاً — فكتابتُه مرّةً تكتبه في كل أمرٍ ورابط."""
    def one(m):
        full = m.group(0).startswith("dms.")
        return '<span data-dom="%s" class="dom">%s</span>' % (
            "full" if full else "root", ESC_FULL if full else ESC_ROOT)

    parts = re.split(r"(<[^>]+>)", html)
    for i in range(0, len(parts), 2):        # المقاطع الفردية وسومٌ — لا تُمَسّ
        parts[i] = DOMAIN_RE.sub(one, parts[i])
    return "".join(parts)


def phase_cards(md_body):
    """جدول «المحتويات» ⟵ شبكةُ بطاقاتٍ للمراحل."""
    rows = re.findall(r"^\|\s*\[([^\]]+)\]\(([^)]+)\)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*$",
                      md_body, flags=re.M)
    if not rows:
        return None
    cards = []
    for key, href, title, need in rows:
        title = re.sub(r"\*\*(.+?)\*\*", r"\1", title)
        title = re.sub(r"[\U0001F300-\U0001FAFF✅⚠️]", "", title).strip()
        need = need.strip()
        meta = "" if need in ("—", "-") else '<span class="m">%s</span>' % need
        cards.append(
            '<a class="pcard" href="%s"><span class="k">%s</span>'
            '<span><span class="t">%s</span>%s</span></a>' % (href, key, title, meta)
        )
    return '<div class="phases">%s</div>' % "".join(cards)


def build_toc(toc_tokens):
    out = ['<ul class="toc">']
    for t in toc_tokens:
        name = re.sub(r"<[^>]+>", "", t["name"]).strip()
        m = re.match(r"^([0-9]{1,2}[ء-ي]?)\)\s*(.*)$", name)
        num, label = (m.group(1), m.group(2)) if m else ("•", name)
        label = re.sub(r"[\U0001F300-\U0001FAFF✅⚠️]", "", label).strip()
        subs = ""
        if t.get("children"):
            kids = []
            for c in t["children"]:
                cname = re.sub(r"<[^>]+>", "", c["name"]).strip()
                cname = re.sub(r"[\U0001F300-\U0001FAFF✅⚠️]", "", cname).strip()
                kids.append('<li><a href="#%s" data-for="%s">%s</a></li>' % (c["id"], c["id"], cname))
            subs = '<ul class="sub">%s</ul>' % "".join(kids)
        out.append(
            '<li><a href="#%s" data-for="%s"><span class="n">%s</span><span>%s</span></a>%s</li>'
            % (t["id"], t["id"], num, label, subs)
        )
    out.append("</ul>")
    return "".join(out)


def main():
    src = read(SRC)

    # ترويسةُ الملفّ (قبل أوّل «## ») تصير افتتاحيةً، والباقي متناً
    split = src.index("\n## ")
    head, body = src[:split], src[split:]

    updated = re.search(r"\*\*آخر تحديث:\*\*\s*([0-9-]+)", head)
    updated = updated.group(1) if updated else ""

    # فقرات الترويسة ذات العلامات تبقى محتوى (تنبيهاتٍ في أعلى المتن)
    intro = [ln[2:] if ln.startswith("> ") else ln[1:]
             for ln in head.split("\n") if ln.startswith(">")]
    intro = "\n".join(intro)
    keep = [p for p in re.split(r"\n(?=[\U0001F300-\U0001FAFF])", intro)
            if re.match(r"^[\U0001F300-\U0001FAFF]", p)]
    intro_md = "\n\n".join("> " + p.replace("\n", "\n> ") for p in keep)

    md = markdown.Markdown(
        extensions=["tables", "fenced_code", "sane_lists", "toc", "attr_list"],
        extension_configs={"toc": {"slugify": slugify, "toc_depth": "2-3"}},
    )
    html = md.convert(intro_md + "\n\n" + body)
    toc_html = build_toc(md.toc_tokens)

    cards = phase_cards(body)
    if cards:
        html = re.sub(r"<table>.*?</table>", cards, html, count=1, flags=re.S)

    html = build_code(html)
    html = build_callouts(html)
    html = build_checklists(html)
    html = build_tables(html)
    html = build_headings(html)
    html = wrap_domains(html)

    n_sections = len(md.toc_tokens)
    n_checks = html.count('type="checkbox"')
    n_cmds = html.count('class="copy"')

    page = PAGE % {
        "css": read(CSS),
        "js": read(JS),
        "toc": toc_html,
        "doc": html,
        "updated": updated,
        "sections": n_sections,
        "checks": n_checks,
        "cmds": n_cmds,
    }
    with io.open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(page)

    kb = len(page.encode("utf-8")) / 1024.0
    msg = ("✔ %s\n  %d مرحلة · %d أمراً قابلاً للنسخ · %d بند تحقّق · %.0f ك.ب\n"
           % (os.path.basename(OUT), n_sections, n_cmds, n_checks, kb))
    sys.stdout.buffer.write(msg.encode("utf-8"))


PAGE = """<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>دليل نشر DMS</title>
<meta name="description" content="المرجع التنفيذيّ الواحد لنشر نظام إدارة الوثائق: من شراء الدومين إلى أوّل كتابٍ رسميّ.">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Amiri:wght@400;700&family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap">
<style>
%(css)s
</style>
</head>
<body>

<header class="topbar">
  <span class="brand"><span class="mark">د</span>دليل النشر — DMS</span>
  <span class="sep"></span>
  <button type="button" class="iconbtn" id="print" title="طباعة أو حفظ PDF">⎙</button>
  <button type="button" class="iconbtn" id="theme" title="المظهر">◐</button>
</header>

<div class="shell">

  <aside class="rail">
    <div class="search">
      <input type="search" id="q" placeholder="ابحث في الدليل…  (Ctrl+K)" aria-label="بحث">
      <span class="ico">⌕</span>
    </div>

    <div class="meter">
      <div class="row"><span class="lab">جاهزية النشر</span><span class="val" id="meter-val">0 / 0</span></div>
      <div class="bar"><i id="meter-bar"></i></div>
      <p class="hint">بنودُ التحقّق في كل المراحل. علاماتُك تُحفظ في هذا المتصفّح.</p>
      <button type="button" class="reset" id="meter-reset">مسح كل العلامات</button>
    </div>

    <h2>المراحل</h2>
    %(toc)s
  </aside>

  <main>
    <div class="doc">

      <section class="hero">
        <p class="eyebrow">أرض العرين للتجارة والمقاولات · DEN LAND</p>
        <h1>من شراء الدومين إلى أوّل كتابٍ رسميّ</h1>
        <p class="sub">المرجع التنفيذيّ الواحد لنشر نظام إدارة الوثائق على سيرفر المكتب —
           مقابَلٌ بالكود سطراً بسطر، لا منقولاً من خطّةٍ سابقة.</p>
        <div class="facts">
          <span>آخر تحديث <b>%(updated)s</b></span>
          <span><b>%(sections)s</b> مرحلة</span>
          <span><b>%(cmds)s</b> أمراً جاهزاً للنسخ</span>
          <span><b>%(checks)s</b> بند تحقّق</span>
        </div>

        <div class="domainbox">
          <label for="domain">اكتب <b>عنوان نظامك النهائيّ</b> مرّةً واحدة — وسيُكتب في
            <b>كل أمرٍ وكل رابطٍ</b> في هذه الصفحة، فتنسخ الأوامر جاهزةً بلا تعديل.</label>
          <div class="in">
            <input type="text" id="domain" placeholder="dms.denland.com" spellcheck="false" autocomplete="off">
            <button type="button" id="domain-apply">اكتبه في الدليل</button>
          </div>
          <p class="note" id="domain-note"></p>
        </div>
      </section>

%(doc)s

    </div>
  </main>
</div>

<button type="button" class="totop" id="totop" title="إلى الأعلى">↑</button>

<script>
%(js)s
</script>
</body>
</html>
"""


if __name__ == "__main__":
    main()
