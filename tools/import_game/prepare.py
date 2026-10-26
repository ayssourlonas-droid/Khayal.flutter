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


def process_html(path: Path, depth: int, removed: list, rewritten: list):
    t = path.read_text(encoding="utf-8", errors="ignore")
    orig = t

    def drop_script(m):
        attrs, body = m.group(1), m.group(2)
        src = re.search(r'src\s*=\s*["\']([^"\']+)["\']', attrs, re.I)
        s = src.group(1) if src else ""
        if s and any(tr in s.lower() for tr in TRACKERS):
            removed.append(f"{path.name}: {s[:90]}")
            return ""
        if not s and INLINE_AD_RE.search(body):
            removed.append(f"{path.name}: سكربت داخلي لإعلانات/تتبّع")
            return ""
        return m.group(0)

    t = SCRIPT_RE.sub(drop_script, t)

    prefix = "../" * depth

    def fix_abs(m):
        val = m.group(3)
        if val == "":
            return f"{m.group(1)}{m.group(2)}#{m.group(2)}" if m.group(1).lower().startswith("href") else m.group(0)
        rewritten.append(f"{path.name}: /{val[:60]}")
        return f"{m.group(1)}{m.group(2)}{prefix}{val}{m.group(2)}"

    t = ATTR_ABS_RE.sub(fix_abs, t)
    if t != orig:
        path.write_text(t, encoding="utf-8")


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
def browser_test(site: Path, work: Path, shot: Path):
    res = {"ran": False, "console_errors": [], "failed_requests": [], "status_ok": False,
           "blank": False, "external_requests": []}
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

            def on_resp(r):
                u = r.url
                if r.status >= 400:
                    res["failed_requests"].append(f"{r.status} {u[:140]}")
                if not u.startswith(f"http://127.0.0.1:{port}"):
                    res["external_requests"].append(u.split("/")[2] if "//" in u else u)

            page.on("response", on_resp)
            resp = page.goto(f"http://127.0.0.1:{port}/game/index.html", wait_until="load", timeout=45000)
            res["status_ok"] = bool(resp and resp.status == 200)
            page.wait_for_timeout(6000)
            info = page.evaluate(
                "() => ({n: document.querySelectorAll('canvas,svg,img,video,iframe,button').length,"
                " t: (document.body ? document.body.innerText : '').trim().length})")
            res["blank"] = info["n"] == 0 and info["t"] < 5
            page.screenshot(path=str(shot))
            b.close()
        res["ran"] = True
    except Exception as e:
        res["console_errors"].append(f"فشل الاختبار الآلي: {str(e)[:200]}")
    finally:
        srv.shutdown()
    res["external_requests"] = sorted(set(res["external_requests"]))[:20]
    res["console_errors"] = res["console_errors"][:12]
    res["failed_requests"] = res["failed_requests"][:12]
    return res


# ───────────── الرئيسي ─────────────
def main():
    repo_url = os.environ.get("INPUT_REPO_URL", "").strip()
    subdir = os.environ.get("INPUT_SUBDIR", "").strip().strip("/")
    build_cmd = os.environ.get("INPUT_BUILD_CMD", "").strip()
    orientation = os.environ.get("INPUT_ORIENTATION", "portrait").strip() or "portrait"
    tags = os.environ.get("INPUT_TAGS", "").strip()
    title_ar = os.environ.get("INPUT_TITLE_AR", "").strip()
    auto_publish = os.environ.get("INPUT_AUTO_PUBLISH", "no").strip().lower()
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
    if s["rewritten"]:
        notes.append(f"حُوّلت {len(s['rewritten'])} مسارات مطلقة في HTML إلى نسبية")
    if s["tracker_hits"]:
        warnings.append("إشارات لمواقع إعلانات/تتبّع داخل الكود لم تُزَل (راجعها): " + "؛ ".join(s["tracker_hits"][:6]))
    if s["external_hosts"]:
        warnings.append("روابط لمواقع خارجية: " + ", ".join(s["external_hosts"][:8]))
    if reasons:
        finish("fail")

    # 5) ترخيص + مصدر داخل مجلد اللعبة
    for fn in os.listdir(src):
        if re.match(r"(?i)^(licen[sc]e|copying|notice)", fn) and (src / fn).is_file():
            shutil.copy2(src / fn, site / fn)
    (site / "SOURCE.txt").write_text(
        f"Source: https://github.com/{owner}/{repo}\nCommit: {sha}\nLicense: {spdx}\n"
        f"Imported: {report['date']}\nChanges: removal of known ad/tracker script tags and conversion of "
        f"root-absolute paths to relative in HTML files only.\n", encoding="utf-8")

    # 6) اختبار
    shot = out / "_shot.png"
    t = browser_test(site, work, shot)
    report["test"] = {k: t[k] for k in ("ran", "status_ok", "blank")}
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
        local_fail = [f for f in t["failed_requests"] if re.match(r"^(4|5)\d\d ", f)]
        if local_fail:
            warnings.append(f"{len(local_fail)} ملفات لم تُحمَّل (404 ونحوه): مثال: {local_fail[0][:100]}")
        if t["console_errors"]:
            warnings.append(f"{len(t['console_errors'])} أخطاء في الكونسول، أولها: {t['console_errors'][0][:100]}")
    if reasons:
        finish("fail")

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
        "year": report["year"], "cover_name": cover_name, "auto_publish": auto_publish,
    }
    (out / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    report["slug"] = slug
    finish("warn" if warnings else "ok")


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
