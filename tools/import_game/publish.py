#!/usr/bin/env python3
"""
المرحلة 2 (فيها الأسرار): نشر الحزمة الجاهزة من prepare.py
  1) ينسخ اللعبة إلى مستودع الاستضافة games/<slug>/
  2) يسجّلها في data_games.json (إن كانت auto_publish=yes والحالة ok) وإلا في data_games_pending.json
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

GAMES, FEATURED, PENDING = "data_games.json", "data_games_featured.json", "data_games_pending.json"


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
    work = Path(os.environ.get("PUBLISH_WORK", "pubwork")).resolve()
    if work.exists():
        shutil.rmtree(work)
    work.mkdir()

    # 1) مستودع الاستضافة
    host = work / "host"
    clone(host_repo, host_branch, host)
    dest = host / "games" / slug
    if dest.exists():
        shutil.rmtree(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(site, dest)
    commit_push(host, host_branch, f"add game {slug} ({meta['license']}) from {meta['source_url']}")

    # 2) سجل البيانات
    data = work / "data"
    clone(data_repo, data_branch, data)
    games, featured, pending = load(data / GAMES), load(data / FEATURED), load(data / PENDING)
    play_url = f"{base_url}/games/{slug}/"
    poster = f"{play_url}{meta['cover_name']}" if meta.get("cover_name") else ""

    existing = None
    for lst in (games, featured, pending):
        for g in lst:
            if str((g.get("details_scene") or {}).get("source_url", "")).rstrip("/") == meta["source_url"].rstrip("/"):
                existing = g
    live = meta.get("auto_publish") == "yes" and report.get("status") == "ok"
    target_name = GAMES if live else PENDING

    if existing:
        msg = f"اللعبة مسجّلة سابقاً (id={existing.get('id')}); حُدّثت ملفاتها فقط ولم يُغيَّر سجلها."
        summary(["## تم النشر", msg, f"الرابط: {play_url}"])
        return

    ids = [int(g.get("id", 0)) for lst in (games, featured, pending) for g in lst if str(g.get("id", "")).lstrip("-").isdigit()]
    new_id = (max(ids) if ids else 0) + 1
    tags = meta.get("tags") or []
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
            "description": meta.get("description", ""),
            "background_url": "",
            "play_url": play_url,
            "developer": meta["developer"],
            "license": meta["license"],
            "source_url": meta["source_url"],
            "orientation": meta["orientation"],
            "category": tags[0] if tags else "",
        },
    }
    target = games if live else pending
    target.append(entry)
    save(data / target_name, target)
    commit_push(data, data_branch, f"add game #{new_id} {meta['title_en']} -> {target_name}")

    summary([
        "## تم النشر ✓",
        f"- الرقم: {new_id}",
        f"- الرابط (يعمل بعد انتهاء نشر الاستضافة): {play_url}",
        f"- أُضيفت إلى: **{target_name}**" + ("" if live else " (قيد المراجعة؛ لن تظهر للاعبين حتى تعتمدها من تطبيق المتحكم)"),
        f"- حالة الاختبار: {report.get('status')}",
    ])


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log("✗", e)
        sys.exit(1)
