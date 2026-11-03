"""تحسين الوسائط: صور→WebP، صوت→Ogg Opus، فيديو→MP4 (H.264)، خطوط→WOFF2.

لكل نوع مرحلة مستقلة: نحوّل، نعدّل أسماء الملفات داخل الكود، نعيد الاختبار في المتصفح.
- مسار مفقود جديد يطابق ملفاً أصلياً حوّلناه ← نستعيد الأصل (نُبقي الاثنين).
- أخطاء جديدة أو صفحة فارغة أو مسار مفقود لا نفهمه ← تراجع كامل عن هذه المرحلة فقط.
لا يُستدعى أي شيء خارجي سوى ffmpeg وPillow وfontTools.
"""
import os
import re
import shutil
import subprocess
from pathlib import Path

IMG_EXT = {".png", ".jpg", ".jpeg", ".gif", ".bmp"}
AUD_EXT = {".mp3", ".wav", ".m4a", ".aac", ".flac"}
VID_EXT = {".mov", ".avi", ".mkv", ".m4v", ".mp4"}
FONT_EXT = {".ttf", ".otf", ".woff"}
TEXT_EXT = {".html", ".htm", ".js", ".mjs", ".css", ".json", ".xml", ".atlas", ".tmx", ".tsx",
            ".txt", ".webmanifest", ".svg", ".plist", ".fnt", ".yml", ".yaml", ".csv", ".tmj"}
DATA_EXT = {".json", ".xml", ".atlas", ".tmx", ".tmj", ".tsx", ".plist", ".fnt"}
NATIVE_PACKS = {".wasm", ".pck", ".unityweb", ".data", ".mem", ".bundle"}
SKIP_NAME = re.compile(r"(?i)(favicon|icon|apple-touch|og-?image|social|preview|thumb|manifest|logo192|logo512)")
ATLAS_NAME = re.compile(r"(?i)(atlas|sprite|sheet|tile|tileset|font|glyph)")
NAME_CH = r"A-Za-z0-9_\-"
MAX_TEXT = 40 * 1024 * 1024


def _run(cmd, timeout=300):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def _rel(site, p):
    return str(Path(p).relative_to(site)).replace(os.sep, "/")


def _walk(site):
    for dp, _, fns in os.walk(site):
        for fn in fns:
            yield Path(dp) / fn


class Journal:
    """يحفظ الأصول لنتمكن من التراجع عن مرحلة كاملة أو استعادة ملف واحد."""

    def __init__(self, site, root):
        self.site, self.root = site, Path(root)
        if self.root.exists():
            shutil.rmtree(self.root)
        self.root.mkdir(parents=True)
        self.saved = set()
        self.created = set()
        self.removed = {}

    def save(self, rel):
        if rel in self.saved:
            return
        src = self.site / rel
        dst = self.root / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        self.saved.add(rel)

    def create(self, rel):
        self.created.add(rel)

    def delete_original(self, rel):
        self.save(rel)
        (self.site / rel).unlink()
        self.removed[rel] = True

    def restore_original(self, rel):
        if rel in self.saved:
            (self.site / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(self.root / rel, self.site / rel)
            self.removed.pop(rel, None)
            return True
        return False

    def rollback(self):
        for rel in self.created:
            p = self.site / rel
            if p.is_file():
                p.unlink()
        for rel in self.saved:
            self.restore_original(rel)


def _load_corpus(site):
    """(rel -> نص) للملفات النصية."""
    out = {}
    for p in _walk(site):
        if p.suffix.lower() in TEXT_EXT:
            try:
                if p.stat().st_size > MAX_TEXT:
                    continue
                out[_rel(site, p)] = p.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
    return out


def _ext_literal_re(exts):
    e = "|".join(re.escape(x.lstrip(".")) for x in exts)
    quoted = re.compile(r"""(['"`])\.(%s)\1""" % e)
    templ = re.compile(r"(\$\{[^}]*\}\.)(%s)(?![A-Za-z0-9])" % e)
    return quoted, templ


def _name_re(name):
    return re.compile(r"(?<![%s.])%s(?![%s])" % (NAME_CH, re.escape(name), NAME_CH))


def _apply_renames(site, journal, renames, ext_map, dyn_exts):
    """renames: {old_name: new_name} (أسماء ملفات بلا مسار). ext_map: {'.png': '.webp'}.
    dyn_exts: امتدادات تُستبدل حرفياً ('.png' داخل نصوص JS) إن وُجد بناء ديناميكي."""
    corpus = _load_corpus(site)
    changed = 0
    quoted = templ = None
    if dyn_exts:
        quoted, templ = _ext_literal_re(dyn_exts)
    pats = [(_name_re(o), n) for o, n in renames.items()]
    for rel, txt in corpus.items():
        new = txt
        for pat, n in pats:
            new = pat.sub(n, new)
        if quoted and Path(rel).suffix.lower() in (".js", ".mjs", ".html", ".htm"):
            new = quoted.sub(lambda m: m.group(1) + ext_map.get("." + m.group(2), "." + m.group(2)) + m.group(1), new)
            new = templ.sub(lambda m: m.group(1) + ext_map.get("." + m.group(2), "." + m.group(2)).lstrip("."), new)
        if new != txt:
            journal.save(rel)
            (site / rel).write_text(new, encoding="utf-8")
            changed += 1
    return changed


def _has_ext_literal(corpus, exts):
    quoted, templ = _ext_literal_re(exts)
    for rel, txt in corpus.items():
        if Path(rel).suffix.lower() in (".js", ".mjs", ".html", ".htm") and (quoted.search(txt) or templ.search(txt)):
            return True
    return False


# ───────────── محوّلات الملفات ─────────────
def _conv_image(src: Path, dst: Path, resize_cap, referenced_by_data):
    from PIL import Image
    im = Image.open(src)
    ext = src.suffix.lower()
    frames = getattr(im, "n_frames", 1)
    if frames > 1 and ext != ".gif":
        return False  # APNG: لا نلمسه
    w, h = im.size
    if im.mode in ("CMYK", "I;16", "I", "F"):
        im = im.convert("RGB")
    elif im.mode == "P":
        im = im.convert("RGBA")
    elif im.mode not in ("RGB", "RGBA", "L", "LA"):
        im = im.convert("RGBA")
    elif im.mode in ("L", "LA"):
        im = im.convert("RGBA" if im.mode == "LA" else "RGB")
    if frames > 1:
        im.save(dst, "WEBP", save_all=True, lossless=True, method=4)
        return True
    cap_hit = max(w, h) > resize_cap and not referenced_by_data and not ATLAS_NAME.search(src.stem)
    if cap_hit:
        k = 2048 / max(w, h)
        im = im.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
    small_flat = False
    if max(w, h) <= 512 and ext in (".png", ".gif", ".bmp"):
        try:
            small_flat = Image.open(src).convert("RGBA").getcolors(maxcolors=256) is not None
        except Exception:
            small_flat = False
    if small_flat or (ext in (".png", ".gif", ".bmp") and max(w, h) <= 128):
        im.save(dst, "WEBP", lossless=True, method=6)
    else:
        im.save(dst, "WEBP", quality=82, method=6)
    return True


def _conv_audio(src: Path, dst: Path):
    ch = ["-ac", "1"] if False else []
    r = _run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-vn", "-c:a", "libopus",
              "-b:a", "80k", "-application", "audio"] + ch + ["-f", "ogg", str(dst)])
    if r.returncode != 0 or not dst.exists():
        r = _run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-vn", "-c:a", "libvorbis",
                  "-q:a", "4", "-f", "ogg", str(dst)])
    return r.returncode == 0 and dst.exists()


def _conv_video(src: Path, dst: Path):
    r = _run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src),
              "-vf", "scale='min(1280,iw)':-2", "-c:v", "libx264", "-preset", "veryfast", "-crf", "28",
              "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart", str(dst)],
             timeout=600)
    return r.returncode == 0 and dst.exists()


def _conv_font(src: Path, dst: Path):
    from fontTools.ttLib import TTFont
    f = TTFont(str(src))
    f.flavor = "woff2"
    f.save(str(dst))
    return dst.exists()


# ───────────── مرحلة واحدة ─────────────
def _stage(site, work, test_fn, base, kind, exts, target_ext, conv, inplace_ok=False):
    res = {"kind": kind, "converted": 0, "saved": 0, "restored": 0, "rolled_back": False, "skipped": 0}
    files = [p for p in _walk(site) if p.suffix.lower() in exts]
    if not files:
        return res
    corpus = _load_corpus(site)
    all_text = "\n".join(corpus.values()) if len(corpus) < 4000 else ""
    dyn = False
    ext_list = sorted({p.suffix.lower() for p in files} - ({target_ext} if inplace_ok else set()))
    if ext_list and kind != "font":
        dyn = _has_ext_literal(corpus, ext_list)
    journal = Journal(site, Path(work) / f"mb_{kind}")
    data_refs = ""
    if kind == "image":
        data_refs = "\n".join(t for r, t in corpus.items() if Path(r).suffix.lower() in DATA_EXT)

    by_name = {}
    for p in files:
        by_name.setdefault(p.name, []).append(p)

    plan = []  # (src_path, dst_path)
    for name, group in by_name.items():
        ok_group = True
        entries = []
        for p in group:
            ext = p.suffix.lower()
            if kind == "image" and SKIP_NAME.search(p.stem):
                ok_group = False
                break
            if inplace_ok and ext == target_ext:
                entries.append((p, p))
                continue
            dst = p.with_suffix(target_ext)
            if dst.exists():
                ok_group = False
                break
            entries.append((p, dst))
        if not ok_group:
            res["skipped"] += len(group)
            continue
        referenced = name in all_text if all_text else any(name in t for t in corpus.values())
        if not (referenced or dyn):
            res["skipped"] += len(group)
            continue
        plan.extend(entries)

    # نفّذ التحويل في مجلد مؤقت داخل الموقع ثم قرّر لكل ملف إن كان أصغر
    done = {}  # rel_src -> (src, dst)
    for src, dst in plan:
        try:
            before = src.stat().st_size
            if before < 2048 and kind != "font":
                continue
            tmp = dst.with_name("._tmp_" + dst.name) if dst != src else src.with_name("._tmp_" + src.name)
            if kind == "image":
                rb = any(src.name in t for t in [data_refs]) if data_refs else False
                ok = _conv_image(src, tmp, 3000, rb)
            elif kind == "audio":
                ok = _conv_audio(src, tmp)
            elif kind == "video":
                if before < 1024 * 1024:
                    continue
                ok = _conv_video(src, tmp)
            else:
                ok = _conv_font(src, tmp)
            if not ok or not tmp.exists():
                if tmp.exists():
                    tmp.unlink()
                continue
            after = tmp.stat().st_size
            if after >= before * 0.95 and not (kind == "font"):
                tmp.unlink()
                continue
            rel_src = _rel(site, src)
            journal.save(rel_src)
            if dst == src:
                shutil.move(str(tmp), str(src))
            else:
                shutil.move(str(tmp), str(dst))
                journal.create(_rel(site, dst))
                src.unlink()
                journal.removed[rel_src] = True
            res["saved"] += before - after
            done[rel_src] = (src, dst)
        except Exception:
            try:
                if tmp.exists():
                    tmp.unlink()
            except Exception:
                pass
            continue
    # مجموعات الأسماء: إن فشل ملف في مجموعة بنفس الاسم تُسترجع المجموعة كلها
    names_done = {}
    for rel, (s, d) in done.items():
        names_done.setdefault(s.name, []).append(rel)
    for name, group in by_name.items():
        got = names_done.get(name, [])
        if got and len(got) != len(group):
            for rel in got:
                s, d = done.pop(rel)
                if d != s and d.exists():
                    d.unlink()
                    journal.created.discard(_rel(site, d))
                journal.restore_original(rel)
    renames = {s.name: d.name for s, d in done.values() if d != s}
    res["converted"] = len(done)
    if not done:
        shutil.rmtree(journal.root, ignore_errors=True)
        return res
    ext_map = {e: target_ext for e in ext_list}
    # الامتداد الحرفي يُستبدل فقط إن كان بقية ملفات ذلك الامتداد محوَّلة أو لها نسخة مطلوبة
    dyn_exts = ext_list if dyn else []
    if renames:
        _apply_renames(site, journal, renames, ext_map, dyn_exts)
        if kind == "font":
            _fix_font_formats(site, journal)
        # في الوضع الديناميكي نضمن وجود هدف لكل ملف أصلي لم يُحوَّل (مثل favicon) بنسخة WebP/OGG
        if dyn_exts and kind in ("image", "audio"):
            for p in list(_walk(site)):
                if p.suffix.lower() in exts and not p.name.startswith("._tmp_"):
                    d = p.with_suffix(target_ext)
                    if not d.exists():
                        try:
                            ok = _conv_image(p, d, 99999, True) if kind == "image" else _conv_audio(p, d)
                        except Exception:
                            ok = False
                        if ok and d.exists():
                            journal.create(_rel(site, d))

    # إعادة اختبار مع استعادة ما تبيّن أن اللعبة تطلبه
    base_missing = {m.lower() for m in base.get("missing", [])}
    base_errs = len(base.get("console_errors", []))
    removed_lower = {}
    for rel in journal.removed:
        removed_lower[rel.lower()] = rel
    for _ in range(4):
        t2 = test_fn()
        if not t2["ran"] or not t2["status_ok"] or t2["blank"] or len(t2["console_errors"]) > base_errs + 2:
            journal.rollback()
            res.update(rolled_back=True, converted=0, saved=0)
            break
        new_missing = [m for m in t2["missing"] if m.lower() not in base_missing]
        if not new_missing:
            break
        fix = [removed_lower[m.lower()] for m in new_missing if m.lower() in removed_lower]
        if not fix or len(fix) < len(new_missing):
            journal.rollback()
            res.update(rolled_back=True, converted=0, saved=0)
            break
        for rel in fix:
            if journal.restore_original(rel):
                res["restored"] += 1
                removed_lower.pop(rel.lower(), None)
    else:
        journal.rollback()
        res.update(rolled_back=True, converted=0, saved=0)
    shutil.rmtree(journal.root, ignore_errors=True)
    return res


def _fix_font_formats(site, journal):
    pat = re.compile(r"""(url\([^)]*\.woff2[^)]*\)\s*format\()(["'])(truetype|opentype|ttf|otf|woff)\2""", re.I)
    for p in _walk(site):
        if p.suffix.lower() in (".css", ".html", ".htm", ".js", ".mjs"):
            try:
                t = p.read_text(encoding="utf-8")
            except Exception:
                continue
            n = pat.sub(lambda m: m.group(1) + m.group(2) + "woff2" + m.group(2), t)
            if n != t:
                journal.save(_rel(site, p))
                p.write_text(n, encoding="utf-8")


# ───────────── الواجهة ─────────────
def optimize(site: Path, work: Path, test_fn, base: dict):
    """test_fn() -> نتيجة browser_test. يعيد قائمة نتائج المراحل + ملاحظات."""
    out = {"stages": [], "skipped_reason": ""}
    exts_present = {p.suffix.lower() for p in _walk(site)}
    if exts_present & NATIVE_PACKS:
        out["skipped_reason"] = "لعبة بمحرك (Unity/Godot/WASM) وسائطها داخل ملفات مجمّعة؛ لم تُحسَّن"
        return out
    try:
        import PIL  # noqa: F401
        have_pil = True
    except Exception:
        have_pil = False
    have_ff = shutil.which("ffmpeg") is not None
    try:
        import fontTools  # noqa: F401
        import brotli  # noqa: F401
        have_ft = True
    except Exception:
        have_ft = False
    plan = []
    if have_pil:
        plan.append(("image", IMG_EXT, ".webp", _conv_image, False))
    if have_ff:
        plan.append(("audio", AUD_EXT, ".ogg", _conv_audio, False))
        plan.append(("video", VID_EXT, ".mp4", _conv_video, True))
    if have_ft:
        plan.append(("font", FONT_EXT, ".woff2", _conv_font, False))
    for kind, exts, target, conv, inplace in plan:
        r = _stage(site, work, test_fn, base, kind, exts, target, conv, inplace_ok=inplace)
        out["stages"].append(r)
    missing = [n for n, ok in (("Pillow", have_pil), ("ffmpeg", have_ff), ("fontTools/brotli", have_ft)) if not ok]
    if missing:
        out["skipped_reason"] = "أدوات غير متوفرة: " + ", ".join(missing)
    return out
