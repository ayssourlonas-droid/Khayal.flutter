"""فحص صحة الألعاب المنشورة: يفتح كل play_url في متصفح headless ويبلّغ عمّا تعطّل.
يعمل أسبوعياً (cron) أو يدوياً. يفشل (exit 1) إن وُجدت لعبة معطلة كي يصلك إشعار من GitHub."""
import json
import os
import sys
import urllib.request
from pathlib import Path

DATA_REPO = os.environ.get("DATA_REPO") or "ayssersalhi-a11y/FlowData_Core"
DATA_BRANCH = os.environ.get("DATA_BRANCH") or "main"
FILES = ["data_games.json", "data_games_featured.json"]
OUT = Path(os.environ.get("HEALTH_OUT", "health_out"))


def fetch(name):
    url = f"https://raw.githubusercontent.com/{DATA_REPO}/{DATA_BRANCH}/{name}"
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception as e:
        print("::warning::تعذّر قراءة", name, str(e)[:100])
        return []


def as_list(d):
    if isinstance(d, list):
        return d
    if isinstance(d, dict):
        out = []
        for v in d.values():
            if isinstance(v, list):
                out += v
        return out
    return []


def main():
    games, seen = [], set()
    for f in FILES:
        for g in as_list(fetch(f)):
            if not isinstance(g, dict):
                continue
            d = g.get("details_scene") or {}
            url = str(d.get("play_url", "")).strip()
            if url.startswith("https://") and url not in seen:
                seen.add(url)
                title = (g.get("main_scene") or {}).get("title_ar") or d.get("source_url") or url
                games.append((g.get("id"), title, url))
    print(f"عدد الألعاب للفحص: {len(games)}")
    OUT.mkdir(parents=True, exist_ok=True)
    results = []
    try:
        from playwright.sync_api import sync_playwright
    except Exception:
        print("::error::Playwright غير مثبّت")
        sys.exit(1)
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        for gid, title, url in games:
            res = {"id": gid, "title": title, "url": url, "ok": False, "problem": ""}
            ctx = browser.new_context(viewport={"width": 412, "height": 915}, is_mobile=True, has_touch=True)
            page = ctx.new_page()
            errs, failed = [], []
            page.on("pageerror", lambda e: errs.append(str(e)[:120]))
            page.on("response", lambda r: failed.append(f"{r.status} {r.url[-60:]}")
                    if r.status >= 400 and "favicon" not in r.url.lower() else None)
            try:
                resp = page.goto(url, wait_until="load", timeout=45000)
                page.wait_for_timeout(6000)
                if resp is None or resp.status != 200:
                    res["problem"] = f"الصفحة لا تُحمَّل (HTTP {resp.status if resp else '؟'})"
                else:
                    info = page.evaluate(
                        "() => ({n: document.querySelectorAll('*').length, c: document.querySelectorAll('canvas,svg,img,video').length,"
                        " t: (document.body && document.body.innerText || '').trim().length})")
                    if info["n"] < 8 or (info["c"] == 0 and info["t"] < 10):
                        res["problem"] = "الصفحة تبدو فارغة"
                    elif failed:
                        res["problem"] = f"{len(failed)} ملفات لم تُحمَّل، مثال: {failed[0]}"
                    elif len(errs) > 3:
                        res["problem"] = f"{len(errs)} أخطاء JavaScript، أولها: {errs[0]}"
                    else:
                        res["ok"] = True
            except Exception as e:
                res["problem"] = "تعذّر الفتح: " + str(e)[:100]
            ctx.close()
            results.append(res)
            print(("✓" if res["ok"] else "✗"), title, res["problem"])
        browser.close()
    bad = [r for r in results if not r["ok"]]
    (OUT / "health.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = [f"## فحص صحة الألعاب", f"سليمة: {len(results) - len(bad)} / {len(results)}", ""]
    for r in bad:
        lines.append(f"- ✗ **{r['title']}** (id {r['id']}): {r['problem']}  \n  {r['url']}")
        print(f"::warning title=لعبة معطلة::{r['title']}: {r['problem']}")
    summ = os.environ.get("GITHUB_STEP_SUMMARY")
    if summ:
        with open(summ, "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
