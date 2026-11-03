#!/usr/bin/env python3
"""
المرحلة 1 (بلا أسرار): جلب لعبة من GitHub، فحص رخصتها، بناؤها إن لزم،
تنظيفها، اختبارها بمتصفح آلي، وتجهيز حزمة جاهزة للنشر في work/out.
لا يستخدم أي ذكاء اصطناعي. التعديل الوحيد على الملفات: إزالة وسوم إعلانات/تتبّع معروفة
وتحويل المسارات المطلقة في ملفات HTML إلى نسبية.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import unquote, urlparse

ALLOWED = ["MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "CC0-1.0", "CC-BY-4.0",
           "CC-BY-3.0", "GPL-3.0", "ISC", "Zlib"]  # OWNED/PARTNER لا تُقبل تلقائياً

PREBUILT_DIRS = ["docs", "dist", "build", "www", "release", "web", "html", "public"]
EXCLUDE_DIRS = {".git", "node_modules", ".github", "__MACOSX"}
MAX_FILE = 25 * 1024 * 1024          # حد Cloudflare Pages للملف الواحد
MAX_FILES = 18000                    # حد Cloudflare 20,000
MAX_TOTAL_FAIL = 150 * 1024 * 1024
MAX_TOTAL_WARN = 60 * 1024 * 1024

TRACKERS = [
    "googlesyndication.com", "doubleclick.net", "google-analytics.com", "googletagmanager.com",
    "adsbygoogle", "facebook.net", "connect.facebook", "unityads", "applovin", "adcolony",
    "ironsrc", "vungle", "chartboost", "admob", "mopub", "popads", "propellerads",
    "adsterra", "taboola", "outbrain", "yandex.ru/metrika", "mc.yandex", "hotjar.com",
    "clarity.ms", "sentry.io", "gameanalytics.com", "poki.com/sdk", "crazygames.com/sdk",
    "gamedistribution.com", "gamemonetize.com", "y8.com", "kongregate.com/javascripts",
]
SAFE_CDNS = {"cdnjs.cloudflare.com", "cdn.jsdelivr.net", "unpkg.com", "fonts.googleapis.com",
             "fonts.gstatic.com", "ajax.googleapis.com", "code.jquery.com", "127.0.0.1", "localhost"}

TEXT_EXT = {".html", ".htm", ".js", ".mjs", ".css", ".json"}

# سجل التعديلات التلقائية (يظهر في التقرير)
FIXES = {}
HTML_SKIPPED = []


def fixed(name, n=1):
    FIXES[name] = FIXES.get(name, 0) + n


# ───────────── أدوات عامة ─────────────
def log(*a):
    print(*a, flush=True)


def run(cmd, cwd=None, timeout=900, check=True, env=None):
    log("$", " ".join(cmd) if isinstance(cmd, list) else cmd)
    e = os.environ.copy()
    e["CI"] = "1"
    if env:
        e.update(env)
    r = subprocess.run(cmd, cwd=cwd, timeout=timeout, env=e, text=True,
                       shell=isinstance(cmd, str),
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    tail = (r.stdout or "")[-2500:]
    if tail:
        log(tail)
    if check and r.returncode != 0:
        raise RuntimeError(f"فشل الأمر: {cmd} (رمز {r.returncode})")
    return r


def parse_repo(url):
    from urllib.parse import urlparse
    u = urlparse(url.strip())
    host = (u.netloc or "").lower()
    segs = [s for s in u.path.split("/") if s]
    if host in ("github.com", "www.github.com") and len(segs) >= 2:
        return segs[0], re.sub(r"\.git$", "", segs[1])
    if host.endswith(".github.io"):
        owner = host.split(".")[0]
        return owner, (segs[0] if segs else f"{owner}.github.io")
    return None


def api(path):
    req = urllib.request.Request("https://api.github.com" + path)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "gamehub-importer")
    tok = os.environ.get("GH_API_TOKEN")
    if tok:
        req.add_header("Authorization", f"Bearer {tok}")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"GitHub API {e.code} لـ {path}")


def slugify(name):
    s = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return s or "game"


def pretty_title(name):
    t = re.sub(r"[-_.]+", " ", name).strip()
    return " ".join(w.capitalize() if w.islower() else w for w in t.split()) or name


# ───────────── اكتشاف مجلد الويب والبناء ─────────────
def has_index(d: Path):
    return (d / "index.html").is_file()


def root_index_needs_build(src: Path):
    p = src / "index.html"
    if not p.is_file():
        return False
    t = p.read_text(encoding="utf-8", errors="ignore")
    return bool(re.search(r'src=["\']/?src/|\.(tsx|jsx|ts)["\']', t))


def find_webroot(src: Path, override=""):
    if override:
        d = (src / override).resolve()
        if str(d).startswith(str(src.resolve())) and has_index(d):
            return d
        return None
    for name in PREBUILT_DIRS:
        d = src / name
        if d.is_dir() and has_index(d):
            return d
    if has_index(src) and not root_index_needs_build(src):
        return src
    return None


def newest_index(src: Path):
    best, best_t = None, 0
    for name in ["dist", "build", "out", "docs", "public", "www"]:
        d = src / name
        if d.is_dir() and has_index(d):
            t = (d / "index.html").stat().st_mtime
            if t >= best_t:
                best, best_t = d, t
    return best


def build_if_needed(src: Path, override, build_cmd, notes):
    root = find_webroot(src, override)
    if root:
        notes.append(f"مجلد الويب الجاهز: {root.relative_to(src) if root != src else '.'}")
        return root
    pkg = src / "package.json"
    if not pkg.is_file():
        return None
    try:
        data = json.loads(pkg.read_text(encoding="utf-8"))
    except Exception:
        data = {}
    scripts = data.get("scripts", {}) if isinstance(data, dict) else {}
    if not build_cmd and "build" not in scripts:
        return None
    notes.append("لا يوجد مجلد جاهز، جارٍ بناء المشروع بـ npm")
    if (src / "package-lock.json").is_file():
        run(["npm", "ci", "--no-audit", "--no-fund"], cwd=src, timeout=900)
    else:
        run(["npm", "install", "--no-audit", "--no-fund"], cwd=src, timeout=900)
    if build_cmd:
        run(build_cmd, cwd=src, timeout=900)  # نص أمر واحد؛ يُنفَّذ عبر الصدفة
    else:
        run(["npm", "run", "build"], cwd=src, timeout=900)
    root = find_webroot(src, override) or newest_index(src)
    return root


# ───────────── التنظيف ─────────────
def copy_site(webroot: Path, dest: Path):
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    for dp, dns, fns in os.walk(webroot):
        dns[:] = [d for d in dns if d not in EXCLUDE_DIRS]
        rel = Path(dp).relative_to(webroot)
        (dest / rel).mkdir(parents=True, exist_ok=True)
        for fn in fns:
            if fn.endswith(".map") or fn == ".DS_Store":
                continue
            sp = Path(dp) / fn
            if sp.is_symlink():
                continue
            shutil.copy2(sp, dest / rel / fn)


SCRIPT_RE = re.compile(r"<script\b([^>]*)>(.*?)</script>", re.I | re.S)
ATTR_ABS_RE = re.compile(r'''(\b(?:src|href|data-src|poster)\s*=\s*)(["'])/(?!/)([^"']*)\2''', re.I)
INLINE_AD_RE = re.compile(r"adsbygoogle|gtag\(|googletag|fbq\(|ga\(\s*['\"]create", re.I)


HTTP_ATTR_RE = re.compile(r"""(\b(?:src|href|data-src|poster)\s*=\s*)(["'])(http://[^"']+)\2""", re.I)


def process_html(path: Path, depth: int, removed: list, rewritten: list):
    raw = path.read_bytes()
    try:
        t = raw.decode("utf-8")
    except UnicodeDecodeError:
        HTML_SKIPPED.append(path.name)  # لا نعدّل ملفاً بترميز غير UTF-8 كي لا نتلفه
        return
    orig = t

    def drop_script(m):
        attrs, body = m.group(1), m.group(2)
        src = re.search(r'src\s*=\s*["\']([^"\']+)["\']', attrs, re.I)
        s = src.group(1) if src else ""
        if s and any(tr in s.lower() for tr in TRACKERS):
            removed.append(f"{path.name}: {s[:90]}")
            fixed("إزالة وسم إعلانات/تتبّع")
            return ""
        if not s and INLINE_AD_RE.search(body):
            removed.append(f"{path.name}: سكربت داخلي لإعلانات/تتبّع")
            fixed("إزالة وسم إعلانات/تتبّع")
            return ""
        return m.group(0)

    t = SCRIPT_RE.sub(drop_script, t)

    prefix = "../" * depth

    def fix_abs(m):
        val = m.group(3)
        if val == "":
            return f"{m.group(1)}{m.group(2)}#{m.group(2)}" if m.group(1).lower().startswith("href") else m.group(0)
        rewritten.append(f"{path.name}: /{val[:60]}")
        fixed("مسار مطلق ← نسبي")
        return f"{m.group(1)}{m.group(2)}{prefix}{val}{m.group(2)}"

    t = ATTR_ABS_RE.sub(fix_abs, t)

    # موارد http:// داخل صفحة https تُحجب من المتصفح (mixed content) ← نرقّيها إلى https
    def to_https(m):
        url = m.group(3)
        if re.match(r"http://(127\.0\.0\.1|localhost)", url):
            return m.group(0)
        fixed("http ← https")
        return f"{m.group(1)}{m.group(2)}https://{url[7:]}{m.group(2)}"

    t = HTTP_ATTR_RE.sub(to_https, t)

    # ترميز UTF-8 صريح إن لم يوجد (يمنع تشويه الحروف العربية)
    hm = re.search(r"<head[^>]*>", t, re.I)
    if hm and not re.search(r"<meta[^>]+charset", t, re.I):
        t = t[:hm.end()] + '<meta charset="utf-8">' + t[hm.end():]
        fixed("إضافة meta charset")

    if t != orig:
        path.write_text(t, encoding="utf-8")


# ───────────── فحص أنماط مريبة (إرشادي؛ لا يمنع النشر لكنه يوقف النشر المباشر) ─────────────
SUSPICIOUS_HIGH = [
    (r"coinhive|coin-hive|cryptonight|cryptoloot|webminer|minero\.cc|jsecoin|stratum\+tcp|authedmine", "تعدين عملات (miner)"),
    (r"eval\s*\(\s*(?:window\.)?atob\s*\(", "تنفيذ كود مشفّر بـ eval(atob(...))"),
    (r"new\s+Function\s*\(\s*(?:window\.)?atob\s*\(", "تنفيذ كود مشفّر بـ Function(atob(...))"),
    (r"document\.write\s*\(\s*unescape\s*\(", "document.write(unescape(...)) — إخفاء كود"),
    (r"(?:window\.)?top\.location(?:\.href)?\s*=\s*[\"']https?://", "إعادة توجيه الصفحة الأم لموقع خارجي"),
]
SUSPICIOUS_MEDIUM = [
    (r"navigator\.sendBeacon\s*\(", "إرسال بيانات خلفياً (sendBeacon)"),
    (r"navigator\.mediaDevices\.getUserMedia|navigator\.getUserMedia", "طلب كاميرا/ميكروفون"),
    (r"navigator\.geolocation", "طلب الموقع الجغرافي"),
    (r"Notification\.requestPermission", "طلب إذن الإشعارات"),
    (r"navigator\.clipboard\.readText", "قراءة الحافظة"),
    (r"new\s+WebSocket\s*\(\s*[\"']wss?://(?!localhost|127\.0\.0\.1)", "اتصال WebSocket بخادم خارجي"),
    (r"(?:window\.)?location(?:\.href)?\s*=\s*[\"']https?://(?!localhost|127\.0\.0\.1)", "إعادة توجيه لموقع خارجي"),
    (r"createElement\s*\(\s*[\"']script[\"']\s*\)[^;]{0,200}\.src\s*=\s*[\"']https?://", "تحميل سكربت خارجي ديناميكياً"),
]


def scan_suspicious(site: Path):
    """يبحث في ملفات JS/HTML عن أنماط معروفة بالإساءة. نتيجة: {'high': [...], 'medium': [...]} (وصف + اسم ملف)."""
    res = {"high": [], "medium": []}
    seen = set()
    comp = [(re.compile(p, re.I), d, "high") for p, d in SUSPICIOUS_HIGH] + \
           [(re.compile(p, re.I), d, "medium") for p, d in SUSPICIOUS_MEDIUM]
    for dp, _, fns in os.walk(site):
        for fn in fns:
            fp = Path(dp) / fn
            if fp.suffix.lower() not in (".js", ".mjs", ".html", ".htm"):
                continue
            try:
                if fp.stat().st_size > 12 * 1024 * 1024:
                    continue
                txt = fp.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            rel = str(fp.relative_to(site)).replace(os.sep, "/")
            for rx, desc, level in comp:
                if (desc, level) in seen:
                    continue
                if rx.search(txt):
                    seen.add((desc, level))
                    res[level].append(f"{desc} ({rel})")
    return res


def sanitize(site: Path):
    removed, rewritten, tracker_hits, ext_hosts = [], [], set(), set()
    files = 0
    total = 0
    big = []
    for dp, dns, fns in os.walk(site):
        for fn in fns:
            p = Path(dp) / fn
            files += 1
            sz = p.stat().st_size
            total += sz
            if sz > MAX_FILE:
                big.append(f"{p.relative_to(site)} ({sz // 1048576}MB)")
            ext = p.suffix.lower()
            if ext in (".html", ".htm"):
                depth = len(p.relative_to(site).parts) - 1
                process_html(p, depth, removed, rewritten)
            if ext in TEXT_EXT and sz <= 6 * 1024 * 1024:
                txt = p.read_text(encoding="utf-8", errors="ignore").lower()
                for tr in TRACKERS:
                    if tr in txt:
                        tracker_hits.add(f"{tr} في {p.relative_to(site)}")
                for h in re.findall(r"https?://([a-z0-9.-]+)", txt):
                    if h not in SAFE_CDNS and "." in h:
                        ext_hosts.add(h)
    return {
        "files": files, "total": total, "big_files": big,
        "removed": removed, "rewritten": rewritten,
        "tracker_hits": sorted(tracker_hits)[:20],
        "external_hosts": sorted(ext_hosts)[:30],
    }


# ───────────── الغلاف ─────────────
COVER_RE = re.compile(r"(cover|thumb|thumbnail|banner|preview|splash|og[-_]?image|icon|logo)", re.I)


def pick_cover(site: Path, src: Path):
    cands = []
    for base in (site, src):
        for dp, dns, fns in os.walk(base):
            dns[:] = [d for d in dns if d not in EXCLUDE_DIRS]
            for fn in fns:
                if fn.lower().endswith((".png", ".jpg", ".jpeg", ".webp")) and COVER_RE.search(fn):
                    p = Path(dp) / fn
                    sz = p.stat().st_size
                    if 8_000 <= sz <= 2_500_000:
                        score = sz + (10_000_000 if "cover" in fn.lower() or "thumb" in fn.lower() else 0)
                        cands.append((score, p))
        if cands:
            break
    if not cands:
        return None
    cands.sort(reverse=True)
    return cands[0][1]


# ───────────── اختبار بمتصفح آلي ─────────────
EXPLORE_KEYS = ["Space", "Enter", "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown",
                "KeyW", "KeyA", "KeyS", "KeyD", "KeyZ", "KeyX", "Escape"]


def _explore(page, w=412, h=915, seconds=45):
    """لاعب آلي عشوائي (monkey test): يلمس ويسحب ويضغط مفاتيح، ويسرّع الزمن الافتراضي للصفحة
    بـ clock.run_for (مؤقتات وrequestAnimationFrame تُنفَّذ فوراً) ليغطي وقتاً لعبياً أطول بكثير من الوقت الحقيقي.
    البذرة ثابتة كي تتشابه جولات المقارنة. لا يستطيع إنهاء مراحل بذكاء؛ هو يوسّع التغطية فقط."""
    import random
    import time
    rnd = random.Random(7)
    t0 = time.time()
    has_clock = hasattr(page, "clock")
    if has_clock:
        try:
            page.clock.install()
        except Exception:
            has_clock = False
    virtual_ms = 0
    try:
        while time.time() - t0 < seconds:
            r = rnd.random()
            if r < 0.45:
                page.touchscreen.tap(rnd.randint(10, w - 10), rnd.randint(10, h - 10))
            elif r < 0.70:
                page.keyboard.press(rnd.choice(EXPLORE_KEYS))
            else:
                x1, y1 = rnd.randint(30, w - 30), rnd.randint(60, h - 60)
                x2, y2 = rnd.randint(30, w - 30), rnd.randint(60, h - 60)
                page.mouse.move(x1, y1)
                page.mouse.down()
                page.mouse.move(x2, y2, steps=6)
                page.mouse.up()
            step = rnd.randint(800, 2500)
            if has_clock:
                try:
                    page.clock.run_for(step)  # يشغّل step ملّي ثانية افتراضية دفعة واحدة
                    virtual_ms += step
                except Exception:
                    has_clock = False
            page.wait_for_timeout(250 if has_clock else step)
    except Exception:
        pass
    return virtual_ms


def browser_test(site: Path, work: Path, shot: Path, explore=False, seconds=45):
    res = {"ran": False, "console_errors": [], "failed_requests": [], "status_ok": False,
           "blank": False, "external_requests": [], "missing": [], "used": []}
    try:
        from playwright.sync_api import sync_playwright
    except Exception:
        return res
    import http.server
    import functools

    serve = work / "serve"
    if serve.exists():
        shutil.rmtree(serve)
    serve.mkdir(parents=True)
    os.symlink(site.resolve(), serve / "game")

    class H(http.server.SimpleHTTPRequestHandler):
        extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                          ".wasm": "application/wasm", ".js": "text/javascript",
                          ".mjs": "text/javascript", ".json": "application/json"}

        def log_message(self, *a):
            pass

    handler = functools.partial(H, directory=str(serve))
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    try:
        with sync_playwright() as pw:
            b = pw.chromium.launch(args=["--no-sandbox"])
            ctx = b.new_context(viewport={"width": 412, "height": 915}, device_scale_factor=2,
                                is_mobile=True, has_touch=True)
            page = ctx.new_page()
            page.on("console", lambda m: res["console_errors"].append(m.text[:200]) if m.type == "error" else None)
            page.on("pageerror", lambda e: res["console_errors"].append(("JS: " + str(e))[:200]))
            page.on("requestfailed", lambda r: res["failed_requests"].append(r.url[:150]))
            used = set()

            def on_req(r):
                u = r.url
                if u.startswith(f"http://127.0.0.1:{port}/game/"):
                    used.add(unquote(urlparse(u).path[len("/game/"):]))

            page.on("request", on_req)

            def on_resp(r):
                u = r.url
                if r.status >= 400:
                    res["failed_requests"].append(f"{r.status} {u[:140]}")
                    if r.status == 404 and u.startswith(f"http://127.0.0.1:{port}/game/"):
                        res["missing"].append(urlparse(u).path[len("/game/"):])
                if not u.startswith(f"http://127.0.0.1:{port}"):
                    res["external_requests"].append(u.split("/")[2] if "//" in u else u)

            page.on("response", on_resp)
            resp = page.goto(f"http://127.0.0.1:{port}/game/index.html", wait_until="load", timeout=45000)
            res["status_ok"] = bool(resp and resp.status == 200)
            page.wait_for_timeout(6000)
            if explore:
                res["virtual_ms"] = _explore(page, 412, 915, seconds)
            info = page.evaluate(
                "() => ({n: document.querySelectorAll('canvas,svg,img,video,iframe,button').length,"
                " t: (document.body ? document.body.innerText : '').trim().length})")
            res["blank"] = info["n"] == 0 and info["t"] < 5
            page.screenshot(path=str(shot))
            res["used"] = sorted(used)
            b.close()
        res["ran"] = True
    except Exception as e:
        res["console_errors"].append(f"فشل الاختبار الآلي: {str(e)[:200]}")
    finally:
        srv.shutdown()
    res["external_requests"] = sorted(set(res["external_requests"]))[:20]
    res["console_errors"] = res["console_errors"][:12]
    res["failed_requests"] = res["failed_requests"][:12]
    res["missing"] = list(dict.fromkeys(res["missing"]))[:400]
    res["used"] = res["used"][:5000]
    return res


# ───────────── إصلاح حالة الأحرف (Linux حساس لها، ويندوز لا) ─────────────
def fix_case(site: Path, missing):
    """ملف مطلوب باسم 'Assets/Hero.PNG' وموجود فعلاً باسم 'assets/hero.png': ننسخه بالاسم المطلوب.
    لا نلمس أي كود؛ نضيف نسخة فقط."""
    index = {}
    for dp, dns, fns in os.walk(site):
        for fn in fns:
            rel = str((Path(dp) / fn).relative_to(site)).replace(os.sep, "/")
            index.setdefault(rel.lower(), rel)
    n = 0
    root = site.resolve()
    for m in missing:
        m = unquote(m).lstrip("/")
        if not m or ".." in m.split("/"):
            continue
        real = index.get(m.lower())
        if not real or real == m:
            continue
        dest = site / m
        try:
            dest.resolve().relative_to(root)
        except ValueError:
            continue
        if not dest.exists():
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(site / real, dest)
            n += 1
        if n >= 300:
            break
    return n


# ───────────── فحص JavaScript بـ ESLint (تقرير فقط، لا يعدّل الكود) ─────────────
VENDOR_RE = re.compile(
    r"(\.min\.|jquery|phaser|three|pixi|howler|lodash|bootstrap|react|vue|angular|babylon|createjs|easeljs|"
    r"tweenjs|soundjs|preloadjs|box2d|matter|cannon|gsap|zepto|underscore|backbone|moment|konva|fabric|kaboom|"
    r"excalibur|melon|crafty|enchant|cocos|emscripten|unity|godot)", re.I)
LINT_RULES = {
    "no-dupe-keys": "error", "no-func-assign": "error", "no-dupe-args": "error",
    "no-const-assign": "error", "no-import-assign": "error", "valid-typeof": "error",
    "use-isnan": "error", "no-unsafe-negation": "error", "no-dupe-else-if": "error",
    "no-unreachable": "warn", "no-self-assign": "warn",
}


def lint_js(site: Path, work: Path):
    res = {"ran": False, "checked": 0, "skipped": 0, "errors": 0, "warnings": 0, "samples": []}
    scripts, modules = [], []
    for dp, dns, fns in os.walk(site):
        for fn in fns:
            if not fn.lower().endswith((".js", ".mjs")):
                continue
            p = Path(dp) / fn
            rel = str(p.relative_to(site)).replace(os.sep, "/")
            sz = p.stat().st_size
            if sz > 400 * 1024 or sz < 20 or VENDOR_RE.search(fn):
                res["skipped"] += 1
                continue
            txt = p.read_text(encoding="utf-8", errors="ignore")
            if sz / (txt.count("\n") + 1) > 200:  # سطور طويلة جداً = مصغّر
                res["skipped"] += 1
                continue
            is_mod = fn.lower().endswith(".mjs") or re.search(r"(?m)^\s*(import\s[^(]|export\s)", txt)
            (modules if is_mod else scripts).append(rel)
    res["checked"] = len(scripts) + len(modules)
    if not res["checked"]:
        return res
    lint_dir = work / "lint"
    lint_dir.mkdir(parents=True, exist_ok=True)
    try:
        run(["npm", "install", "--prefix", str(lint_dir), "eslint@9", "--no-audit", "--no-fund"], timeout=300)
    except Exception as e:
        res["error"] = f"تعذّر تثبيت ESLint: {str(e)[:80]}"
        return res
    eslint = lint_dir / "node_modules" / "eslint" / "bin" / "eslint.js"
    rules = json.dumps(LINT_RULES)
    for kind, files in (("script", scripts), ("module", modules)):
        if not files:
            continue
        cfg = lint_dir / f"cfg_{kind}.mjs"
        cfg.write_text(
            'export default [{files:["**/*.js","**/*.mjs"],'
            f'languageOptions:{{ecmaVersion:"latest",sourceType:"{kind}"}},rules:{rules}}}];\n',
            encoding="utf-8")
        for i in range(0, len(files), 80):
            chunk = files[i:i + 80]
            try:
                r = subprocess.run(["node", str(eslint), "-c", str(cfg), "-f", "json", "--no-warn-ignored", *chunk],
                                   cwd=site, capture_output=True, text=True, timeout=300)
                data = json.loads(r.stdout or "[]")
            except Exception:
                continue
            res["ran"] = True
            for f in data:
                for m in f.get("messages", []):
                    if m.get("severity") == 2:
                        res["errors"] += 1
                        if len(res["samples"]) < 8:
                            rel = os.path.relpath(f.get("filePath", ""), site)
                            res["samples"].append(f"{rel}:{m.get('line', '?')} {str(m.get('message', ''))[:80]}")
                    else:
                        res["warnings"] += 1
    return res


# ───────────── تقليل الملفات (حذف ما لا تحتاجه اللعبة، مع تحقق بالتجربة) ─────────────
PRUNE_EXTS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".ico", ".svg",              # صور
    ".mp3", ".ogg", ".wav", ".m4a", ".aac", ".flac", ".mp4", ".webm", ".mov", ".avi",  # صوت/فيديو
    ".ttf", ".otf", ".woff", ".woff2", ".eot",                                      # خطوط
    ".psd", ".xcf", ".blend", ".ai", ".kra", ".sketch", ".fig", ".aseprite",        # أعمال الفنان
    ".zip", ".rar", ".7z", ".tar", ".gz", ".pdf", ".md",                           # أرشيف/توثيق
}
CORPUS_EXTS = {".html", ".htm", ".js", ".mjs", ".css", ".json", ".xml", ".svg", ".atlas", ".fnt", ".tmx",
               ".tsx", ".plist", ".yml", ".yaml", ".csv", ".webmanifest", ".manifest", ".txt"}
JUNK_NAMES = re.compile(
    r"^(package(-lock)?\.json|yarn\.lock|pnpm-lock\.yaml|tsconfig.*\.json|\.eslintrc.*|\.prettierrc.*|"
    r"\.editorconfig|\.gitignore|\.gitattributes|\.npmrc|\.babelrc|webpack\.config\..*|rollup\.config\..*|"
    r"vite\.config\..*|gulpfile\..*|gruntfile\..*|makefile|dockerfile|\.travis\.yml|appveyor\.yml|"
    r"changelog.*|contributing.*|code_of_conduct.*)$", re.I)
JUNK_DIRS = {"test", "tests", "__tests__", "spec", "screenshots", "screenshot", "promo", "marketing", ".idea", ".vscode"}
KEEP_RE = re.compile(r"^(licen[sc]e|copying|notice|source\.txt|_cover\.)", re.I)


def _rel(site, p):
    return str(p.relative_to(site)).replace(os.sep, "/")


def build_tokens(site: Path, skip: set):
    toks = set()
    for dp, dns, fns in os.walk(site):
        for fn in fns:
            p = Path(dp) / fn
            if p.suffix.lower() not in CORPUS_EXTS or _rel(site, p) in skip:
                continue
            try:
                if p.stat().st_size > 8 * 1024 * 1024:
                    continue
                txt = p.read_text(encoding="utf-8", errors="ignore").lower()
            except OSError:
                continue
            toks.update(re.findall(r"[a-z0-9_\-\.]{3,}", txt))
    return toks


def find_prune_candidates(site: Path, used: set, mode: str):
    """يرجع قائمة مسارات نرى أنها غير لازمة، ويُتحقَّق منها بعدها بالتجربة."""
    files = []
    for dp, dns, fns in os.walk(site):
        for fn in fns:
            files.append(Path(dp) / fn)
    rels = [_rel(site, f) for f in files]
    used_l = {u.lower() for u in used}

    def is_junk(rel):
        parts = rel.split("/")
        if KEEP_RE.match(parts[-1]) or rel.lower() == "index.html":
            return False
        if JUNK_NAMES.match(parts[-1]):
            return True
        if any(d.lower() in JUNK_DIRS for d in parts[:-1]):
            return True
        if Path(parts[-1]).suffix.lower() in {".psd", ".xcf", ".blend", ".ai", ".kra", ".sketch", ".fig", ".aseprite", ".md"}:
            return True
        return False

    junk = {r for r in rels if is_junk(r)}
    tokens = build_tokens(site, junk)

    def referenced(rel):
        name = rel.split("/")[-1].lower()
        stem = name.rsplit(".", 1)[0] if "." in name else name
        if rel.lower() in used_l or name in tokens:
            return True
        return len(stem) < 3 or stem in tokens

    cands = {r for r in junk if not referenced(r)}
    if mode != "smart":
        return sorted(cands)

    # ملفات الوسائط: نبحث عن غير المشار إليها وغير المطلوبة أثناء التجربة
    by_dir = {}
    for r in rels:
        by_dir.setdefault(os.path.dirname(r), []).append(r)

    explicit_dir = {d: any(referenced(f) for f in fl) for d, fl in by_dir.items()}

    def dir_dynamic(d):
        while d:
            name = d.split("/")[-1].lower()
            if d in by_dir and not explicit_dir[d] and (len(name) < 3 or name in tokens):
                return True
            d = os.path.dirname(d)
        return False

    fam = {}
    for r in rels:
        name = r.split("/")[-1].lower()
        stem, _, ext = name.rpartition(".")
        key = (os.path.dirname(r), re.sub(r"\d+", "#", stem), ext)
        fam.setdefault(key, []).append(r)

    def family_protected(r):
        name = r.split("/")[-1].lower()
        stem, _, ext = name.rpartition(".")
        key = (os.path.dirname(r), re.sub(r"\d+", "#", stem), ext)
        members = fam[key]
        if any(referenced(m) for m in members):
            return True
        prefix = re.split(r"\d", stem, maxsplit=1)[0]
        return len(members) > 1 and (len(prefix) < 3 or prefix in tokens)

    for r in rels:
        name = r.split("/")[-1]
        if KEEP_RE.match(name) or Path(name).suffix.lower() not in PRUNE_EXTS or r in cands:
            continue
        if referenced(r) or dir_dynamic(os.path.dirname(r)) or family_protected(r):
            continue
        cands.add(r)
    return sorted(cands)


def prune_site(site: Path, work: Path, shot: Path, base: dict, mode: str):
    """يحجر الملفات المرشّحة، يعيد الاختبار، ويستعيد ما تبيّن أن اللعبة تطلبه.
    إن ساء الاختبار بشكل عام يتراجع عن كل شيء."""
    result = {"mode": mode, "removed": [], "restored": 0, "rolled_back": False, "bytes": 0}
    cands = find_prune_candidates(site, set(base.get("used", [])), mode)
    if not cands:
        return result
    quarantine = work / "quarantine"
    if quarantine.exists():
        shutil.rmtree(quarantine)
    quarantine.mkdir(parents=True)
    moved = {}
    for r in cands:
        src = site / r
        if not src.is_file():
            continue
        dst = quarantine / r
        dst.parent.mkdir(parents=True, exist_ok=True)
        moved[r] = src.stat().st_size
        shutil.move(str(src), str(dst))

    def restore(rel):
        if rel in moved:
            (site / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(quarantine / rel), str(site / rel))
            del moved[rel]
            return True
        return False

    base_missing = {m.lower() for m in base.get("missing", [])}
    base_errs = len(base.get("console_errors", []))
    for _ in range(4):
        t2 = browser_test(site, work, shot, explore=True, seconds=40)
        if not t2["ran"] or not t2["status_ok"] or t2["blank"] or len(t2["console_errors"]) > base_errs + 2:
            for r in list(moved):
                restore(r)
            result["rolled_back"] = True
            break
        lower_map = {m.lower(): m for m in moved}
        need = [lower_map[m.lower()] for m in t2["missing"] if m.lower() in lower_map and m.lower() not in base_missing]
        if not need:
            break
        for r in need:
            if restore(r):
                result["restored"] += 1
    else:
        # لم نستقر بعد 4 جولات: تراجع كامل للأمان
        for r in list(moved):
            restore(r)
        result["rolled_back"] = True

    result["removed"] = sorted(moved.items(), key=lambda kv: -kv[1])
    result["bytes"] = sum(moved.values())
    shutil.rmtree(quarantine, ignore_errors=True)
    return result


# ───────────── الرئيسي ─────────────
def main():
    repo_url = os.environ.get("INPUT_REPO_URL", "").strip()
    subdir = os.environ.get("INPUT_SUBDIR", "").strip().strip("/")
    build_cmd = os.environ.get("INPUT_BUILD_CMD", "").strip()
    orientation = os.environ.get("INPUT_ORIENTATION", "portrait").strip() or "portrait"
    tags = os.environ.get("INPUT_TAGS", "").strip()
    title_ar = os.environ.get("INPUT_TITLE_AR", "").strip()
    auto_publish = os.environ.get("INPUT_AUTO_PUBLISH", "no").strip().lower()
    prune_mode = os.environ.get("INPUT_PRUNE", "smart").strip().lower()
    if prune_mode not in ("smart", "junk", "off"):
        prune_mode = "smart"
    media_mode = os.environ.get("INPUT_MEDIA", "safe").strip().lower()
    if media_mode not in ("safe", "off"):
        media_mode = "safe"
    work = Path(os.environ.get("WORK_DIR", "work")).resolve()
    out = work / "out"
    if work.exists():
        shutil.rmtree(work)
    out.mkdir(parents=True)

    reasons, warnings, notes = [], [], []

    def finish(status):
        report["status"] = status
        report["reasons"] = reasons
        report["warnings"] = warnings
        report["notes"] = notes
        (out / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        write_summary(report)
        emit_annotations(report)
        if status == "fail":
            log("✗ فشل:", "; ".join(reasons))
            sys.exit(1)

    report = {"repo_url": repo_url, "date": datetime.now(timezone.utc).isoformat()}

    pr = parse_repo(repo_url)
    if not pr:
        reasons.append("الرابط ليس مستودع GitHub (أو صفحة github.io)")
        finish("fail")
    owner, repo = pr
    report.update(owner=owner, repo=repo)

    # 1) الرخصة
    try:
        info = api(f"/repos/{owner}/{repo}")
    except Exception as e:
        reasons.append(str(e))
        finish("fail")
    lic = info.get("license") or {}
    spdx = lic.get("spdx_id") if isinstance(lic, dict) else None
    report["license"] = spdx
    if info.get("private"):
        reasons.append("المستودع خاص")
    if not spdx:
        reasons.append("لا توجد رخصة في المستودع (كل الحقوق محفوظة)")
    elif spdx not in ALLOWED:
        reasons.append(f"الرخصة {spdx} غير مسموحة للاستيراد التلقائي")
    if reasons:
        finish("fail")
    notes.append("فحص الرخصة يخص الكود فقط؛ راجع حقوق الصور والأصوات يدوياً")

    # 2) الجلب
    src = work / "src"
    run(["git", "clone", "--depth", "1", f"https://github.com/{owner}/{repo}.git", str(src)], timeout=600)
    sha = run(["git", "rev-parse", "HEAD"], cwd=src).stdout.strip().splitlines()[-1]
    report["commit"] = sha
    report["repo_size_kb"] = int(info.get("size") or 0)
    report["description"] = (info.get("description") or "").strip()
    report["topics"] = info.get("topics") or []
    pushed = (info.get("pushed_at") or "")[:4]
    report["year"] = pushed or str(datetime.now().year)
    report["owner_login"] = (info.get("owner") or {}).get("login", owner)

    # 3) مجلد الويب
    try:
        webroot = build_if_needed(src, subdir, build_cmd, notes)
    except Exception as e:
        reasons.append(f"فشل البناء: {e}")
        finish("fail")
    if not webroot:
        reasons.append("لم أجد نسخة ويب (index.html) ولا أمر بناء. قد يكون مشروع Unity/Godot مصدرياً. "
                       "جرّب إدخال subdir أو build_cmd")
        finish("fail")

    # 4) تنظيف
    site = out / "site"
    copy_site(webroot, site)
    s = sanitize(site)
    report["stats"] = {k: s[k] for k in ("files", "total")}
    if s["files"] > MAX_FILES:
        reasons.append(f"عدد الملفات {s['files']} يتجاوز {MAX_FILES}")
    if s["total"] > MAX_TOTAL_FAIL:
        reasons.append(f"الحجم {s['total'] // 1048576}MB كبير جداً")
    elif s["total"] > MAX_TOTAL_WARN:
        warnings.append(f"الحجم كبير: {s['total'] // 1048576}MB")
    if s["big_files"]:
        reasons.append("ملفات تتجاوز 25MB (حد Cloudflare): " + ", ".join(s["big_files"][:5]))
    if s["removed"]:
        warnings.append(f"أُزيلت {len(s['removed'])} وسوم إعلانات/تتبّع من HTML")
    report["removed_tags"] = s["removed"][:20]
    if HTML_SKIPPED:
        warnings.append("ملفات HTML بترميز غير UTF-8 لم تُعدَّل: " + ", ".join(HTML_SKIPPED[:5]))
    if s["tracker_hits"]:
        warnings.append("إشارات لمواقع إعلانات/تتبّع داخل الكود لم تُزَل (راجعها): " + "؛ ".join(s["tracker_hits"][:6]))
    if s["external_hosts"]:
        warnings.append("روابط لمواقع خارجية: " + ", ".join(s["external_hosts"][:8]))
    sus = scan_suspicious(site)
    report["suspicious"] = sus
    if sus["high"]:
        warnings.append("⛔ أنماط مريبة جداً (راجع الكود قبل أي نشر): " + "؛ ".join(sus["high"][:5]))
    if sus["medium"]:
        notes.append("أنماط تستحق الانتباه: " + "؛ ".join(sus["medium"][:6]))
    if reasons:
        finish("fail")

    # 4ب) عزل بيانات اللعبة (localStorage/IndexedDB/Cache) عن بقية الألعاب على نفس النطاق
    try:
        import isolate_storage
        n_iso = isolate_storage.inject(site, slugify(repo))
        if n_iso:
            fixed("عزل تخزين اللعبة", n_iso)
            notes.append(f"عُزل تخزين اللعبة عن باقي الألعاب (بادئة khayal:{slugify(repo)}:) في {n_iso} صفحة")
    except Exception as e:
        warnings.append(f"تعذّر عزل التخزين: {str(e)[:100]}")

    # 5) ترخيص + مصدر داخل مجلد اللعبة
    for fn in os.listdir(src):
        if re.match(r"(?i)^(licen[sc]e|copying|notice)", fn) and (src / fn).is_file():
            shutil.copy2(src / fn, site / fn)

    # 6) اختبار
    shot = out / "_shot.png"
    t = browser_test(site, work, shot, explore=True, seconds=60)
    if t["ran"] and t["missing"]:
        n_alias = fix_case(site, t["missing"])
        if n_alias:
            fixed("نسخ ملفات بحالة الأحرف المطلوبة", n_alias)
            t = browser_test(site, work, shot, explore=True, seconds=60)
    report["test"] = {k: t[k] for k in ("ran", "status_ok", "blank")}
    if t.get("virtual_ms"):
        notes.append(f"لاعب آلي عشوائي: جُرّب نحو {t['virtual_ms'] // 1000} ثانية لعب افتراضية خلال 60 ثانية حقيقية")
    report["console_errors"] = t["console_errors"]
    report["failed_requests"] = t["failed_requests"]
    report["external_requests"] = t["external_requests"]
    if not t["ran"]:
        warnings.append("لم يعمل الاختبار الآلي (Playwright)")
    else:
        if not t["status_ok"]:
            reasons.append("index.html لا يُحمَّل (ليس 200)")
        if t["blank"]:
            reasons.append("الصفحة فارغة بعد 6 ثوانٍ")
        local_fail = [f for f in t["failed_requests"]
                      if re.match(r"^(4|5)\d\d ", f) and "favicon" not in f.lower()]
        if local_fail:
            warnings.append(f"{len(local_fail)} ملفات لم تُحمَّل (404 ونحوه): مثال: {local_fail[0][:100]}")
        if t["console_errors"]:
            warnings.append(f"{len(t['console_errors'])} أخطاء في الكونسول، أولها: {t['console_errors'][0][:100]}")
    if reasons:
        finish("fail")

    # 6أ) تقليل الملفات
    files_before = sum(len(f) for _, _, f in os.walk(site))
    if spdx == "GPL-3.0" and prune_mode != "off":
        notes.append("رخصة GPL-3.0: لم تُحذف أي ملفات (يجب إتاحة المصدر كاملاً)")
        prune_mode = "off"
    if prune_mode != "off" and t["ran"]:
        pr = prune_site(site, work, shot, t, prune_mode)
        n_rm = len(pr["removed"])
        report["prune"] = {"mode": prune_mode, "removed": n_rm, "bytes": pr["bytes"],
                           "restored": pr["restored"], "rolled_back": pr["rolled_back"]}
        if pr["rolled_back"]:
            warnings.append("حذف الملفات سبّب أخطاء في الاختبار فتم التراجع عنه كاملاً (اللعبة بقيت كما هي)")
        elif n_rm:
            files_after = sum(len(f) for _, _, f in os.walk(site))
            notes.append(f"تقليل الملفات: حُذف {n_rm} ملفاً ({pr['bytes'] // 1024} KB)؛ من {files_before} إلى {files_after}"
                         + (f"؛ استُعيد {pr['restored']} ملفاً تبيّن أن اللعبة تطلبه" if pr["restored"] else ""))
            (out / "pruned.txt").write_text(
                "\n".join(f"{sz}\t{rel}" for rel, sz in pr["removed"]), encoding="utf-8")
            fixed("حذف ملفات غير لازمة", n_rm)
        else:
            notes.append("تقليل الملفات: لا ملفات يمكن حذفها بأمان")

    # 6أ-2) تحسين الوسائط (صور/صوت/فيديو/خطوط)
    if media_mode != "off" and t["ran"]:
        if spdx == "GPL-3.0":
            notes.append("رخصة GPL-3.0: لم تُحسَّن الوسائط")
        else:
            try:
                import optimize_media
                size_before = sum(f.stat().st_size for f in site.rglob("*") if f.is_file())
                mo = optimize_media.optimize(
                    site, work, lambda: browser_test(site, work, shot, explore=True, seconds=40), t)
                size_after = sum(f.stat().st_size for f in site.rglob("*") if f.is_file())
                report["media"] = {"stages": mo["stages"], "before": size_before, "after": size_after}
                if mo["skipped_reason"]:
                    notes.append("تحسين الوسائط: " + mo["skipped_reason"])
                names = {"image": "صور", "audio": "صوت", "video": "فيديو", "font": "خطوط"}
                for st in mo["stages"]:
                    if st["rolled_back"]:
                        warnings.append(f"تحسين {names[st['kind']]} سبّب أخطاء في الاختبار فتم التراجع عنه")
                    elif st["converted"]:
                        notes.append(f"تحسين {names[st['kind']]}: {st['converted']} ملفاً، وفّر {st['saved'] // 1024} KB"
                                     + (f"؛ استُعيد {st['restored']} أصلياً تبيّن أن اللعبة تطلبه" if st["restored"] else ""))
                        fixed("تحسين وسائط " + names[st["kind"]], st["converted"])
                if size_before > size_after:
                    notes.append(f"حجم اللعبة بعد تحسين الوسائط: {size_before // 1048576}MB ← {size_after // 1048576}MB "
                                 "(الاختبار الآلي لا يغطي كل المراحل؛ جرّب اللعبة بنفسك)")
            except Exception as e:
                warnings.append(f"تعذّر تحسين الوسائط: {str(e)[:120]}")

    # 6ب) فحص JavaScript (تقرير فقط)
    lint = lint_js(site, work)
    report["lint"] = lint
    if lint.get("error"):
        warnings.append(lint["error"])
    elif lint["errors"]:
        warnings.append(f"ESLint: {lint['errors']} أخطاء برمجية في {lint['checked']} ملفات، أولها: {lint['samples'][0]}")
    elif lint["ran"]:
        notes.append(f"ESLint: لا أخطاء في {lint['checked']} ملفات")
    if lint["skipped"]:
        notes.append(f"{lint['skipped']} ملفات JS مصغّرة أو من مكتبات معروفة لم تُفحص")

    # سجل التعديلات التلقائية
    for k, v in FIXES.items():
        notes.append(f"تعديل تلقائي: {k} × {v}")
    report["fixes"] = dict(FIXES)
    (site / "SOURCE.txt").write_text(
        f"Source: https://github.com/{owner}/{repo}\nCommit: {sha}\nLicense: {spdx}\n"
        f"Imported: {report['date']}\nAutomated changes (see report): {json.dumps(FIXES, ensure_ascii=False)}\n",
        encoding="utf-8")

    # 7) الغلاف
    cover = pick_cover(site, src)
    cover_name = ""
    if cover:
        cover_name = "_cover" + cover.suffix.lower()
        shutil.copy2(cover, site / cover_name)
        notes.append(f"الغلاف من ملف اللعبة: {cover.name}")
    elif shot.is_file():
        cover_name = "_cover.png"
        shutil.copy2(shot, site / cover_name)
        warnings.append("لا توجد صورة غلاف؛ استُخدمت لقطة شاشة (يُفضّل استبدالها)")

    slug = slugify(repo)
    meta = {
        "slug": slug, "title_en": pretty_title(repo), "title_ar": title_ar,
        "description": report["description"], "developer": report["owner_login"],
        "license": spdx, "source_url": f"https://github.com/{owner}/{repo}",
        "orientation": orientation if orientation in ("portrait", "landscape", "both") else "portrait",
        "tags": [x.strip() for x in re.split(r"[,،]", tags) if x.strip()] or report["topics"][:3],
        "year": report["year"], "repo_size_kb": report.get("repo_size_kb", 0), "cover_name": cover_name, "auto_publish": auto_publish,
        "suspicious_high": report.get("suspicious", {}).get("high", []),
    }
    (out / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    report["slug"] = slug
    finish("warn" if warnings else "ok")


def _esc(t):
    return t.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


def emit_annotations(r):
    """ملاحظات GitHub (تظهر في تطبيق Game Control داخل تفاصيل التشغيل)."""
    notes = r.get("notes") or []
    warns = r.get("warnings") or []
    if notes:
        body = _esc("\n".join("• " + x for x in notes))
        print(f"::notice title=تقرير الاستيراد ({r.get('status')})::{body}", flush=True)
    if warns:
        body = _esc("\n".join("• " + x for x in warns))
        print(f"::warning title=تحذيرات الاستيراد::{body}", flush=True)


def write_summary(r):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    lines = [f"## استيراد لعبة: {r.get('repo_url', '')}", f"**الحالة: {r.get('status')}**", ""]
    for k, title in (("reasons", "أسباب الفشل"), ("warnings", "تحذيرات"), ("notes", "ملاحظات")):
        if r.get(k):
            lines.append(f"### {title}")
            lines += [f"- {x}" for x in r[k]]
            lines.append("")
    txt = "\n".join(lines)
    log(txt)
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(txt + "\n")


if __name__ == "__main__":
    main()
