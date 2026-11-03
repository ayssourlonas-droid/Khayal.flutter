#!/usr/bin/env python3
"""
اختبار لعبة بلاعب ذكي (نموذج ذكاء اصطناعي يرى الصور).
يعمل في job منفصل فيه المفتاح؛ لا يبني ولا يشغّل أي كود من اللعبة إلا داخل متصفح معزول.

الحلقة: لقطة شاشة ← النموذج يقرر حركة ← ننفّذها ← نُقدّم ساعة اللعبة الافتراضية ← من جديد.
ساعة اللعبة متوقفة أثناء تفكير النموذج (Playwright clock)، فلا تفوتها شيئاً.

يدعم أي مزوّد متوافق مع OpenAI (chat/completions مع صور) + صيغة Anthropic (إن احتوى الرابط anthropic.com).
لا يفشل أبداً: عند أي مشكلة يكتب التقرير مع حقل error ويخرج بنجاح.
"""
import base64
import functools
import http.server
import json
import os
import re
import shutil
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

W, H = 412, 915
KEYS_OK = re.compile(r"^(Space|Enter|Escape|Arrow(Left|Right|Up|Down)|Key[A-Z]|Digit[0-9])$")

SYSTEM = (
    "You are a QA tester playing a web game in a phone browser (screen 412x915 CSS pixels, touch only unless "
    "the game clearly needs a keyboard). Your goals: start the game, make real progress, and notice problems "
    "(blank or broken screens, overlapping UI, unreadable text, controls that do nothing, ads or links leaving the game). "
    "Reply with ONE JSON object only, no prose, no code fences."
)

STEP_PROMPT = """Step {i} of {n}.
What you did so far:
{hist}

Look at the screenshot. Reply with JSON:
{{"observation": "one short sentence about what you see",
  "action": {{"type": "tap", "x": 0, "y": 0}}  OR  {{"type": "key", "key": "Space"}}  OR  {{"type": "swipe", "x1": 0, "y1": 0, "x2": 0, "y2": 0}}  OR  {{"type": "wait"}}  OR  {{"type": "done"}},
  "issue": null or "a problem you noticed"}}
Use "done" only if the game is clearly unplayable or you reached the end."""

FINAL_PROMPT = """Here are your notes while playing:
{hist}

Now write the final QA report as ONE JSON object:
{{"playable": true or false or null,
  "summary_ar": "ملخص بالعربية من جملتين: هل تعمل اللعبة وهل هي مفهومة",
  "description_ar": "وصف تسويقي بالعربية من جملتين لهذه اللعبة",
  "tags": ["up to 3 lowercase english genre tags, e.g. puzzle, arcade, racing"],
  "issues": ["short problems found, in Arabic"],
  "kid_safe": true or false or null}}"""


def log(*a):
    print(*a, flush=True)


def esc(t):
    return t.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


def is_anthropic(url):
    return "anthropic.com" in url


def call_model(endpoint, key, model, system, text, image_b64=None, max_tokens=700):
    headers = {"Content-Type": "application/json"}
    if is_anthropic(endpoint):
        headers["x-api-key"] = key
        headers["anthropic-version"] = "2023-06-01"
        content = []
        if image_b64:
            content.append({"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": image_b64}})
        content.append({"type": "text", "text": text})
        payload = {"model": model, "max_tokens": max_tokens, "system": system,
                   "messages": [{"role": "user", "content": content}]}
    else:
        headers["Authorization"] = f"Bearer {key}"
        content = [{"type": "text", "text": text}]
        if image_b64:
            content.append({"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + image_b64}})
        payload = {"model": model, "max_tokens": max_tokens, "temperature": 0.2,
                   "messages": [{"role": "system", "content": system}, {"role": "user", "content": content}]}
    last = ""
    for attempt in range(4):
        try:
            req = urllib.request.Request(endpoint, data=json.dumps(payload).encode("utf-8"), headers=headers, method="POST")
            with urllib.request.urlopen(req, timeout=120) as r:
                data = json.loads(r.read().decode("utf-8"))
            if is_anthropic(endpoint):
                return "".join(c.get("text", "") for c in data.get("content", []) if isinstance(c, dict))
            return data["choices"][0]["message"]["content"] or ""
        except urllib.error.HTTPError as e:
            body = ""
            try:
                body = e.read().decode("utf-8", "ignore")[:200]
            except Exception:
                pass
            last = f"HTTP {e.code} {body}"
            if e.code in (429, 500, 502, 503, 529) and attempt < 3:
                time.sleep(15 * (attempt + 1))
                continue
            raise RuntimeError(last)
        except Exception as e:
            last = str(e)[:160]
            if attempt < 3:
                time.sleep(5)
                continue
            raise RuntimeError(last)
    raise RuntimeError(last)


def parse_json(text):
    t = (text or "").strip()
    t = re.sub(r"^```(?:json)?|```$", "", t, flags=re.M).strip()
    try:
        return json.loads(t)
    except Exception:
        pass
    m = re.search(r"\{.*\}", t, re.S)
    if m:
        try:
            return json.loads(m.group(0))
        except Exception:
            return None
    return None


def clamp(v, lo, hi):
    try:
        return max(lo, min(hi, int(v)))
    except Exception:
        return lo


def shot_b64(page):
    return base64.b64encode(page.screenshot(type="jpeg", quality=60)).decode("ascii")


def run_agent(site: Path, endpoint, key, model, steps):
    from playwright.sync_api import sync_playwright
    serve = Path("aiserve")
    if serve.exists():
        shutil.rmtree(serve)
    serve.mkdir()
    os.symlink(site.resolve(), serve / "game")

    class H_(http.server.SimpleHTTPRequestHandler):
        extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm",
                          ".js": "text/javascript", ".mjs": "text/javascript", ".json": "application/json"}

        def log_message(self, *a):
            pass

    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(H_, directory=str(serve)))
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()

    report = {"steps": 0, "notes": [], "issues": [], "console_errors": [], "virtual_ms": 0}
    try:
        with sync_playwright() as pw:
            b = pw.chromium.launch(args=["--no-sandbox"])
            ctx = b.new_context(viewport={"width": W, "height": H}, device_scale_factor=1, is_mobile=True, has_touch=True)
            page = ctx.new_page()
            page.on("console", lambda m: report["console_errors"].append(m.text[:160]) if m.type == "error" else None)
            page.on("pageerror", lambda e: report["console_errors"].append(("JS: " + str(e))[:160]))
            has_clock = hasattr(page, "clock")
            if has_clock:
                try:
                    page.clock.install()
                except Exception:
                    has_clock = False
            page.goto(f"http://127.0.0.1:{port}/game/index.html", wait_until="load", timeout=45000)
            page.wait_for_timeout(3000)
            paused = False
            if has_clock:
                try:
                    page.clock.pause_at(datetime.now(timezone.utc) + timedelta(seconds=5))
                    paused = True
                except Exception:
                    paused = False
            report["clock"] = "paused" if paused else ("running" if has_clock else "none")

            hist = []
            last_img = None
            for i in range(1, steps + 1):
                img = shot_b64(page)
                last_img = img
                prompt = STEP_PROMPT.format(i=i, n=steps, hist="\n".join(hist[-6:]) or "(nothing yet)")
                out = parse_json(call_model(endpoint, key, model, SYSTEM, prompt, img, 400))
                if not isinstance(out, dict):
                    hist.append(f"{i}. (unparsable reply)")
                    continue
                obs = str(out.get("observation", ""))[:160]
                act = out.get("action") if isinstance(out.get("action"), dict) else {"type": "wait"}
                issue = out.get("issue")
                if issue:
                    report["issues"].append(str(issue)[:160])
                typ = str(act.get("type", "wait"))
                desc = typ
                try:
                    if typ == "tap":
                        x, y = clamp(act.get("x"), 1, W - 1), clamp(act.get("y"), 1, H - 1)
                        page.touchscreen.tap(x, y)
                        desc = f"tap({x},{y})"
                    elif typ == "key" and KEYS_OK.match(str(act.get("key", ""))):
                        page.keyboard.press(str(act["key"]))
                        desc = f"key {act['key']}"
                    elif typ == "swipe":
                        x1, y1 = clamp(act.get("x1"), 1, W - 1), clamp(act.get("y1"), 1, H - 1)
                        x2, y2 = clamp(act.get("x2"), 1, W - 1), clamp(act.get("y2"), 1, H - 1)
                        page.mouse.move(x1, y1)
                        page.mouse.down()
                        page.mouse.move(x2, y2, steps=8)
                        page.mouse.up()
                        desc = f"swipe({x1},{y1}->{x2},{y2})"
                    elif typ == "done":
                        report["notes"].append(f"{i}. {obs} [done]")
                        report["steps"] = i
                        break
                except Exception as e:
                    desc += f" (failed: {str(e)[:60]})"
                if paused:
                    try:
                        page.clock.run_for(2000)
                        report["virtual_ms"] += 2000
                    except Exception:
                        paused = False
                page.wait_for_timeout(400 if paused else 1500)
                hist.append(f"{i}. saw: {obs} | did: {desc}")
                report["notes"].append(f"{i}. {obs} → {desc}")
                report["steps"] = i

            if last_img is not None:
                final = parse_json(call_model(endpoint, key, model, SYSTEM,
                                              FINAL_PROMPT.format(hist="\n".join(hist[-25:]) or "(none)"), shot_b64(page), 700))
                if isinstance(final, dict):
                    for k in ("playable", "summary_ar", "description_ar", "tags", "issues", "kid_safe"):
                        if k in final:
                            report["final_" + k] = final[k]
            b.close()
    finally:
        srv.shutdown()
    return report


def main():
    pkg = Path(os.environ.get("PKG_DIR", "pkg")).resolve()
    out_dir = Path(os.environ.get("AI_OUT", "ai_out"))
    out_dir.mkdir(parents=True, exist_ok=True)
    key = os.environ.get("AI_API_KEY", "").strip()
    endpoint = os.environ.get("AI_ENDPOINT", "").strip()
    model = os.environ.get("AI_MODEL", "").strip()
    try:
        steps = max(3, min(60, int(os.environ.get("AI_STEPS", "20"))))
    except ValueError:
        steps = 20
    result = {"model": model}

    def done(extra):
        result.update(extra)
        (out_dir / "ai_report.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        lines = []
        if result.get("error"):
            lines.append("تعذّر الاختبار الذكي: " + result["error"])
        else:
            lines.append(f"خطوات: {result.get('steps')} · ساعة اللعبة: {result.get('clock')} · لعب افتراضي: {result.get('virtual_ms', 0) // 1000} ث")
            if result.get("final_playable") is not None:
                lines.append("تعمل؟ " + ("نعم" if result["final_playable"] else "لا"))
            if result.get("final_summary_ar"):
                lines.append(str(result["final_summary_ar"]))
            for it in (result.get("final_issues") or result.get("issues") or [])[:5]:
                lines.append("⚠ " + str(it))
        body = esc("\n".join("• " + l for l in lines))
        level = "warning" if result.get("error") or result.get("final_playable") is False else "notice"
        print(f"::{level} title=اختبار اللاعب الذكي::{body}", flush=True)
        sp = os.environ.get("GITHUB_STEP_SUMMARY")
        if sp:
            with open(sp, "a", encoding="utf-8") as f:
                f.write("## اختبار اللاعب الذكي\n" + "\n".join("- " + l for l in lines) + "\n")

    if not (key and endpoint and model):
        done({"error": "لم تُضبط الأسرار AI_API_KEY وAI_ENDPOINT وAI_MODEL"})
        return
    if not endpoint.startswith("https://"):
        done({"error": "رابط النموذج يجب أن يبدأ بـ https://"})
        return
    site = pkg / "site"
    if not (site / "index.html").is_file():
        done({"error": "لا توجد حزمة لعبة لاختبارها"})
        return
    try:
        done(run_agent(site, endpoint, key, model, steps))
    except Exception as e:
        msg = str(e).replace(key, "***")[:200]
        done({"error": msg})


if __name__ == "__main__":
    main()
