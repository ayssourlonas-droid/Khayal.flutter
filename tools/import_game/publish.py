#!/usr/bin/env python3
"""
المرحلة 2 (فيها الأسرار): نشر الحزمة الجاهزة من prepare.py
  1) ينسخ اللعبة إلى مستودع الاستضافة games/<slug>/
  2) يسجّلها في data_games.json (إن كانت auto_publish=yes والحالة ok) وإلا في data_games_pending.json
"""
import html
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

GAMES, FEATURED, PENDING = "data_games.json", "data_games_featured.json", "data_games_pending.json"


def name_key(name):
    """يطابق nameKey في تطبيق Game Control: أحرف صغيرة، بلا . _ - ومسافات، بلا أرقام (وإن لم يبقَ شيء نقارن بالأرقام)."""
    base = re.sub(r"[\s._\-]", "", str(name).lower())
    letters = re.sub(r"[0-9]", "", base)
    return letters or base


def similar_size(a, b):
    a, b = int(a or 0), int(b or 0)
    if a <= 0 or b <= 0:
        return False
    return (max(a, b) - min(a, b)) / max(a, b) <= 0.15


def write_credits(host_dir: Path, index):
    """يولّد legal/credits.html (+credits.json) من سجل الاستيراد: حقوق كل لعبة ومطورها ورخصتها ومصدرها."""
    items = [e for e in index if isinstance(e, dict) and e.get("slug")]
    legal = host_dir / "legal"
    legal.mkdir(parents=True, exist_ok=True)
    rows = []
    for e in sorted(items, key=lambda x: str(x.get("title", "")).lower()):
        esc = lambda k: html.escape(str(e.get(k, "") or ""))
        src = esc("source")
        lic_file = e.get("license_file")
        lic_link = (f' · <a href="../games/{html.escape(e["slug"])}/{html.escape(lic_file)}">نص الرخصة</a>' if lic_file else "")
        rows.append(
            f'<section id="{esc("slug")}"><h2>{esc("title")}</h2>'
            f'<p>المطوّر: <b>{esc("developer")}</b></p>'
            f'<p>الرخصة: <b>{esc("license")}</b>{lic_link}</p>'
            f'<p>المصدر: <a href="{src}" rel="noopener">{src}</a></p>'
            f'<p class="m">نسخة المصدر: {esc("commit")[:10]} · تاريخ الاستيراد: {esc("date")}</p></section>'
        )
    doc = (
        '<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        "<title>حقوق الألعاب والمطورين</title>"
        "<style>body{font-family:system-ui,sans-serif;background:#0d0817;color:#eee;max-width:760px;margin:0 auto;padding:20px;line-height:1.7}"
        "a{color:#e7ff14}section{border:1px solid #4a2468;border-radius:14px;padding:6px 16px;margin:14px 0;background:#1a0f26}"
        "h1{color:#e7ff14}h2{margin:10px 0 4px}.m{color:#aaa;font-size:.85em}</style></head><body>"
        "<h1>حقوق الألعاب والمطورين</h1>"
        "<p>الألعاب في هذا التطبيق مفتوحة المصدر أو مرخّصة لإعادة التوزيع، وتعود حقوقها لأصحابها المذكورين أدناه. "
        "فحص الرخصة يخص الكود؛ وقد تخضع الصور والأصوات لتراخيص مستقلة مذكورة في مستودع كل لعبة. "
        "إن كنت صاحب حق وتريد تعديل البيانات أو إزالة لعبة فراسلنا.</p>"
        + "".join(rows) + "</body></html>"
    )
    (legal / "credits.html").write_text(doc, encoding="utf-8")
    (legal / "credits.json").write_text(json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8")
    return True


def log(*a):
    print(*a, flush=True)


def sh(cmd, cwd=None, check=True):
    safe = [re.sub(r"x-access-token:[^@]+@", "x-access-token:***@", c) for c in cmd]
    log("$", " ".join(safe))
    r = subprocess.run(cmd, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = re.sub(r"x-access-token:[^@\s]+@", "x-access-token:***@", r.stdout or "")
    if out.strip():
        log(out[-1500:])
    if check and r.returncode != 0:
        raise RuntimeError(f"فشل: {safe[:3]}")
    return r


def remote(repo):
    tpl = os.environ.get("GIT_REMOTE_TEMPLATE")  # للاختبار المحلي فقط
    if tpl:
        return tpl.format(repo=repo)
    tok = os.environ["PUBLISH_TOKEN"]
    return f"https://x-access-token:{tok}@github.com/{repo}.git"


def clone(repo, branch, dest):
    sh(["git", "clone", "--depth", "1", "--branch", branch, remote(repo), str(dest)])
    sh(["git", "config", "user.name", "game-importer"], cwd=dest)
    sh(["git", "config", "user.email", "game-importer@users.noreply.github.com"], cwd=dest)


def commit_push(repo_dir, branch, message):
    sh(["git", "add", "-A"], cwd=repo_dir)
    if sh(["git", "diff", "--cached", "--quiet"], cwd=repo_dir, check=False).returncode == 0:
        log("لا تغييرات للنشر")
        return False
    sh(["git", "commit", "-m", message], cwd=repo_dir)
    for i in range(4):
        r = sh(["git", "push", "origin", f"HEAD:{branch}"], cwd=repo_dir, check=False)
        if r.returncode == 0:
            return True
        sh(["git", "pull", "--rebase", "origin", branch], cwd=repo_dir, check=False)
        time.sleep(3 * (i + 1))
    raise RuntimeError("تعذّر الدفع بعد عدة محاولات")


def as_list(data):
    out = []
    if isinstance(data, list):
        out = [x for x in data if isinstance(x, dict)]
    elif isinstance(data, dict):
        for v in data.values():
            if isinstance(v, list):
                out += [x for x in v if isinstance(x, dict)]
    return out


def load(path: Path):
    if not path.is_file():
        return []
    try:
        return as_list(json.loads(path.read_text(encoding="utf-8") or "[]"))
    except Exception:
        raise RuntimeError(f"{path.name} ليس JSON صالحاً؛ لن أكتب فوقه")


def save(path: Path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def summary(lines):
    txt = "\n".join(lines)
    log(txt)
    p = os.environ.get("GITHUB_STEP_SUMMARY")
    if p:
        with open(p, "a", encoding="utf-8") as f:
            f.write(txt + "\n")


def main():
    pkg = Path(os.environ.get("PKG_DIR", "pkg")).resolve()
    meta = json.loads((pkg / "meta.json").read_text(encoding="utf-8"))
    report = json.loads((pkg / "report.json").read_text(encoding="utf-8"))
    site = pkg / "site"

    host_repo = os.environ["HOST_REPO"]
    host_branch = os.environ.get("HOST_BRANCH") or "main"
    base_url = os.environ["HOST_BASE_URL"].rstrip("/")
    data_repo = os.environ.get("DATA_REPO") or "ayssersalhi-a11y/FlowData_Core"
    data_branch = os.environ.get("DATA_BRANCH") or "main"
    slug = meta["slug"]
    if slug in ("api", "www", "stats", "legal", "admin"):
        slug += "-game"  # أسماء محجوزة لنطاقات الخدمة
    work = Path(os.environ.get("PUBLISH_WORK", "pubwork")).resolve()
    if work.exists():
        shutil.rmtree(work)
    work.mkdir()

    # 1) مستودع الاستضافة
    host = work / "host"
    clone(host_repo, host_branch, host)

    def push_host(extra_index=None):
        """دفعة واحدة إلى مستودع الاستضافة (كل دفعة = بناء واحد في Cloudflare، وحدّه المجاني نحو 500 شهرياً)."""
        dest = host / "games" / slug
        if dest.exists():
            shutil.rmtree(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(site, dest)
        if extra_index is not None:
            try:
                write_credits(host, extra_index)
            except Exception as e:
                log("تعذّر توليد صفحة الحقوق:", e)
        commit_push(host, host_branch, f"add game {slug} ({meta['license']}) from {meta['source_url']}")

    # 2) سجل البيانات
    data = work / "data"
    clone(data_repo, data_branch, data)
    games, featured, pending = load(data / GAMES), load(data / FEATURED), load(data / PENDING)
    tpl = (os.environ.get("PLAY_URL_TEMPLATE") or "").strip()
    # مع Worker النطاقات الفرعية: https://{slug}.games.example.com/  (عزل حقيقي لكل لعبة) وإلا المسار العادي
    play_url = tpl.format(slug=slug) if tpl and "{slug}" in tpl else f"{base_url}/games/{slug}/"
    poster = f"{play_url}{meta['cover_name']}" if meta.get("cover_name") else ""

    existing = None
    for lst in (games, featured, pending):
        for g in lst:
            if str((g.get("details_scene") or {}).get("source_url", "")).rstrip("/") == meta["source_url"].rstrip("/"):
                existing = g
    ai = {}
    ai_path = Path(os.environ.get("AI_DIR", str(pkg.parent / "ai"))) / "ai_report.json"
    if ai_path.exists():
        try:
            ai = json.loads(ai_path.read_text(encoding="utf-8"))
        except Exception:
            ai = {}
    if ai.get("error"):
        ai = {}
    live = meta.get("auto_publish") == "yes" and report.get("status") == "ok"
    if ai and ai.get("final_playable") is False:
        live = False  # الذكاء الاصطناعي لم يعتبرها قابلة للعب -> مراجعة بشرية
    if ai and ai.get("final_kid_safe") is False:
        live = False
    # مقارنة بسجل الأسماء السابق (اسم + حجم المستودع) لكشف التكرار
    INDEX = "data_import_index.json"
    index = as_list(load(data / INDEX))
    key = name_key(meta["source_url"].rstrip("/").split("/")[-1])
    size_kb = int(meta.get("repo_size_kb") or 0)
    seen = [e for e in index if isinstance(e, dict) and e.get("key") == key]
    for lst in (games, featured, pending):
        for g in lst:
            u = str((g.get("details_scene") or {}).get("source_url", "")).rstrip("/")
            if u and name_key(u.split("/")[-1]) == key and not any(e.get("repo") and e["repo"] in u for e in seen):
                seen.append({"key": key, "size": 0, "repo": u.split("github.com/")[-1]})
    review_note = ""
    if any(similar_size(e.get("size"), size_kb) for e in seen):
        review_note = "مكررة محتملة: اسم وحجم مشابهان للعبة مسجّلة (" + ", ".join(str(e.get("repo")) for e in seen[:2]) + ")"
        live = False
    elif seen:
        review_note = "اسم مشابه للعبة مسجّلة (" + ", ".join(str(e.get("repo")) for e in seen[:2]) + ") بحجم مختلف"
        live = False  # اسم مشابه: لا نشر مباشر؛ مراجعة بشرية
    if meta.get("suspicious_high"):
        live = False
        note2 = "أنماط مريبة جداً: " + "؛ ".join(meta["suspicious_high"][:3])
        review_note = (review_note + " | " if review_note else "") + note2
    target_name = GAMES if live else PENDING

    if existing:
        push_host()
        msg = f"اللعبة مسجّلة سابقاً (id={existing.get('id')}); حُدّثت ملفاتها فقط ولم يُغيَّر سجلها."
        summary(["## تم النشر", msg, f"الرابط: {play_url}"])
        return

    ids = [int(g.get("id", 0)) for lst in (games, featured, pending) for g in lst if str(g.get("id", "")).lstrip("-").isdigit()]
    new_id = (max(ids) if ids else 0) + 1
    tags = meta.get("tags") or ((ai.get("final_tags") or []) if ai else [])
    if isinstance(tags, str):
        tags = [t.strip() for t in tags.split(",") if t.strip()]
    description = meta.get("description") or (ai.get("final_description_ar") or "")
    entry = {
        "id": new_id,
        "release_year": str(meta.get("year", "")),
        "category_tags": tags,
        "main_scene": {
            "title_ar": meta.get("title_ar") or meta["title_en"],
            "title_en": meta["title_en"],
            "app_rating": 0.0,
            "poster_url": poster,
        },
        "details_scene": {
            "description": description,
            "background_url": "",
            "play_url": play_url,
            "developer": meta["developer"],
            "license": meta["license"],
            "source_url": meta["source_url"],
            "orientation": meta["orientation"],
            "type": "web",
            "category": tags[0] if tags else "",
        },
    }
    if review_note:
        entry["review_note"] = review_note
    target = games if live else pending
    target.append(entry)
    save(data / target_name, target)
    lic_file = ""
    for fn in sorted(os.listdir(site)):
        if re.match(r"(?i)^(licen[sc]e|copying)", fn) and (site / fn).is_file():
            lic_file = fn
            break
    index.append({
        "key": key, "size": size_kb, "repo": meta["source_url"].split("github.com/")[-1].rstrip("/"), "id": new_id,
        "slug": slug, "title": meta.get("title_ar") or meta["title_en"], "developer": meta["developer"],
        "license": meta["license"], "source": meta["source_url"], "commit": str(report.get("commit", "")),
        "date": str(report.get("date", ""))[:10], "license_file": lic_file,
    })
    save(data / INDEX, index)
    push_host(index)  # ملفات اللعبة + صفحة الحقوق في دفعة واحدة، ثم نسجّلها في البيانات
    commit_push(data, data_branch, f"add game #{new_id} {meta['title_en']} -> {target_name}")

    summary([
        "## تم النشر ✓",
        f"- الرقم: {new_id}",
        f"- الرابط (يعمل بعد انتهاء نشر الاستضافة): {play_url}",
        f"- أُضيفت إلى: **{target_name}**" + ("" if live else " (قيد المراجعة؛ لن تظهر للاعبين حتى تعتمدها من تطبيق المتحكم)"),
        f"- حالة الاختبار: {report.get('status')}",
    ] + ([f"- ⚠ {review_note}"] if review_note else [])
      + ([f"- تقييم الذكاء الاصطناعي: قابلة للعب={ai.get('final_playable')} — {ai.get('final_summary_ar','')}"] if ai else []))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log("✗", e)
        sys.exit(1)
