/// سكربت يُحقن في صفحة اللعبة عند اللعب ويستبدل نصوصها بلغة اللاعب من قاموس `_i18n.json` الخاص باللعبة.
/// لا يعدّل ملفات اللعبة: يعترض رسم النص في canvas (fillText/strokeText/measureText)، ويترجم نصوص DOM وسماتها
/// (title/alt/placeholder/aria-label وأزرار value) مع مراقبة التغييرات، وكذلك alert/confirm/prompt وعنوان الصفحة.
///
/// القاعدة التي يجب أن تبقى متطابقة مع الخط (tools/import_game/i18n_build.py::norm_key وI18N_HARVEST_JS):
/// يُطبَّع النص بطي المسافات والقص، ثم تُستبدل كل سلسلة أرقام (\d+(?:[.,]\d+)*) بـ {#}.
/// وقيمة الترجمة تحمل {1} و{2}… بترتيب ظهور الأرقام في الأصل، فتعود الأرقام الأصلية إلى مكانها.
///
/// الاستعمال: '$kI18nLoaderJs(${jsonEncode({'lang': 'fr', 'map': {...}, 'rt': true})});'
/// rt=true: ما لا مفتاح له (نص بُني وقت اللعب أو جاء من خادم) يُرسَل دفعات إلى التطبيق عبر قناة KhayalI18n
/// فيترجمه على الجهاز ويعيده بـ window.__khayalI18n.add(map).
const String kI18nLoaderJs = r"""
(function (CFG) {
  'use strict';
  try {
    var W = window;
    if (W.__khayalI18n) { if (W.__khayalI18n.scan) W.__khayalI18n.scan(); return; }
    var MAP = (CFG && CFG.map) || {};
    var NUM = /\d+(?:[.,]\d+)*/g;
    var has = Object.prototype.hasOwnProperty;
    // أنماط {*}: نبنيها مرة واحدة. شرط الأمان: 5 حروف حرفية على الأقل ولا نمط يبدأ وينتهي بمتغيّر فقط.
    var PATS = [], MISS = {}, MISSN = 0;
    // ترجمة وقت اللعب لما لا مفتاح له: نص لاتيني قصير يشبه واجهة، مرة واحدة لكل نص، بسقف 400 نص لكل صفحة.
    var RT = !!(CFG && CFG.rt && W.KhayalI18n && typeof W.KhayalI18n.postMessage === 'function');
    var ASKED = {}, ASKN = 0, QUEUE = [], QT = null, OUT = {};
    function want(key) {
      if (!RT || ASKN >= 400 || has.call(ASKED, key) || has.call(OUT, key)) return;
      if (key.length > 200 || !/^[\x20-\x7E]+$/.test(key)) return;            // لاتيني بسيط فقط (المصدر إنجليزي)
      if ((key.match(/[A-Za-z]/g) || []).length < 3) return;
      if (/[<>{}=;\\]|https?:|www\.|\.(?:js|png|jpg|json|mp3)\b|^[a-z]+[A-Z]|_[a-z]/.test(key.replace(/\{#\}/g, ''))) return;
      ASKED[key] = 1; ASKN++; QUEUE.push(key);
      if (!QT) QT = setTimeout(flush, 350);
    }
    function flush() {
      QT = null;
      try {
        while (QUEUE.length) W.KhayalI18n.postMessage(JSON.stringify(QUEUE.splice(0, 30)));
      } catch (e) {}
    }
    try {
      Object.keys(MAP).forEach(function (k) {
        if (PATS.length >= 100 || k.indexOf('{*}') < 0) return;
        var lit = k.replace(/\{[#*]\}/g, '');
        if ((lit.match(/[^\W\d_]/g) || []).length < 5) return;
        var src = k.split(/(\{[#*]\})/).map(function (x) {
          if (x === '{#}') return '(\\d+(?:[.,]\\d+)*)';
          if (x === '{*}') return '(.{1,40}?)';
          return x.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        }).join('');
        // قيمة الترجمة: {n} بترتيب ظهور المتغيّرات ({#} و{*}) في المفتاح
        PATS.push({ re: new RegExp('^' + src + '$'), val: String(MAP[k]) });
      });
    } catch (e) { PATS = []; }

    // مطابقة تامة لنص قصير (بلا أنماط). تُستعمل لترجمة قيم المتغيّرات داخل الأنماط.
    function exact(v) {
      if (!/[^\W\d_]/.test(v)) return null; // أرقام/رموز فقط
      var c = v.replace(/\s+/g, ' ').trim();
      var nn = [];
      var k = c.replace(NUM, function (x) { nn.push(x); return '{#}'; });
      if (!has.call(MAP, k) || k.indexOf('{*}') >= 0) return null;
      return String(MAP[k]).replace(/\{(\d+)\}/g, function (_, i) { return nn[+i - 1] == null ? '' : nn[+i - 1]; });
    }

    function lookup(s) {
      if (typeof s !== 'string') return null;
      var m = /^(\s*)([\s\S]*?)(\s*)$/.exec(s);
      var core = m[2].replace(/\s+/g, ' ');
      if (core.length < 2 || core.length > 300) return null;
      var nums = [];
      var key = core.replace(NUM, function (x) { nums.push(x); return '{#}'; });
      if (has.call(MAP, key)) {
        var out = String(MAP[key]).replace(/\{(\d+)\}/g, function (_, i) {
          var v = nums[+i - 1];
          return v == null ? '' : v;
        });
        OUT[out.trim()] = 1;
        return m[1] + out + m[3];
      }
      if (has.call(OUT, core)) return null; // هذا النص ناتج ترجمتنا نفسها: لا نعيد ترجمته
      // حل أخير: أنماط بمتغيّر نصي {*} (مثل «Hello {*}, welcome!»). النتيجة (وكذلك الإخفاق) تُخزَّن كي لا
      // تُجرَّب الأنماط في كل إطار رسم.
      if (!PATS.length) { want(key); return null; }
      if (has.call(MISS, core)) return MISS[core] === 0 ? null : m[1] + MISS[core] + m[3];
      var res = 0;
      for (var p = 0; p < PATS.length && !res; p++) {
        var mm = PATS[p].re.exec(core);
        if (mm) res = PATS[p].val.replace(/\{(\d+)\}/g, function (_, i) {
          var v = mm[+i];
          if (v == null) return '';
          // المتغيّر قد يكون نصاً من بيانات اللعبة (اسم عنصر…): نترجمه بمطابقة تامة فقط إن وُجد مفتاحه (بلا أنماط، فلا تداخل)
          var t = exact(v);
          return t == null ? v : t;
        });
      }
      if (MISSN++ > 3000) { MISS = {}; MISSN = 0; }
      MISS[core] = res;
      if (!res) want(key); else OUT[res.trim()] = 1;
      return res ? m[1] + res + m[3] : null;
    }

    // ── رسم النص في canvas (يغطي Phaser وكل الألعاب التي ترسم نصها) ──
    [W.CanvasRenderingContext2D, W.OffscreenCanvasRenderingContext2D].forEach(function (C) {
      if (!C || !C.prototype) return;
      ['fillText', 'strokeText', 'measureText'].forEach(function (k) {
        var o = C.prototype[k];
        if (typeof o !== 'function' || o.__kh) return;
        var f = function (t) {
          var a = arguments;
          try {
            var r = lookup(String(t));
            if (r != null) { a = Array.prototype.slice.call(arguments); a[0] = r; }
          } catch (e) {}
          return o.apply(this, a);
        };
        f.__kh = 1;
        C.prototype[k] = f;
      });
    });

    // ── نوافذ المتصفح ──
    ['alert', 'confirm', 'prompt'].forEach(function (k) {
      var o = W[k];
      if (typeof o !== 'function') return;
      W[k] = function (m) {
        var a = Array.prototype.slice.call(arguments);
        try { var r = lookup(String(m)); if (r != null) a[0] = r; } catch (e) {}
        return o.apply(W, a);
      };
    });

    // ── DOM ──
    var SKIP = {SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEXTAREA: 1, CODE: 1, PRE: 1};
    var ATTRS = ['title', 'alt', 'placeholder', 'aria-label'];
    function fix(n) {
      if (!n) return;
      if (n.nodeType === 3) {
        var p = n.parentNode;
        if (p && SKIP[p.nodeName]) return;
        var r = lookup(n.nodeValue);
        if (r != null && r !== n.nodeValue) n.nodeValue = r;
        return;
      }
      if (n.nodeType !== 1 || SKIP[n.nodeName]) return;
      if (n.getAttribute) {
        for (var i = 0; i < ATTRS.length; i++) {
          var v = n.getAttribute(ATTRS[i]);
          if (v) { var r2 = lookup(v); if (r2 != null && r2 !== v) n.setAttribute(ATTRS[i], r2); }
        }
        if (n.nodeName === 'INPUT' && /^(button|submit|reset)$/i.test(n.getAttribute('type') || '')) {
          var vv = n.getAttribute('value');
          if (vv) { var r3 = lookup(vv); if (r3 != null && r3 !== vv) n.setAttribute('value', r3); }
        }
      }
      for (var c = n.firstChild; c; ) { var nx = c.nextSibling; fix(c); c = nx; }
    }
    function scan() {
      try {
        if (W.document && W.document.documentElement) fix(W.document.documentElement);
        if (W.document && W.document.title) { var t = lookup(W.document.title); if (t != null) W.document.title = t; }
      } catch (e) {}
    }
    if (W.MutationObserver && W.document && W.document.documentElement) {
      new W.MutationObserver(function (ms) {
        for (var i = 0; i < ms.length; i++) {
          var m = ms[i];
          if (m.type === 'childList') { for (var j = 0; j < m.addedNodes.length; j++) fix(m.addedNodes[j]); }
          else fix(m.target);
        }
      }).observe(W.document.documentElement,
        {childList: true, characterData: true, subtree: true, attributes: true, attributeFilter: ATTRS});
    }
    // يستقبل ترجمات وقت اللعب من التطبيق: {مفتاح: قيمة بـ{1}{2}…} ثم يعيد المسح
    function add(m) {
      try {
        for (var k in m) if (has.call(m, k) && typeof m[k] === 'string') MAP[k] = m[k];
        MISS = {}; MISSN = 0; scan();
      } catch (e) {}
    }
    W.__khayalI18n = {scan: scan, lookup: lookup, add: add, lang: CFG && CFG.lang};
    scan();
    if (W.document && W.document.addEventListener) W.document.addEventListener('DOMContentLoaded', scan);
  } catch (e) {}
})
""";
