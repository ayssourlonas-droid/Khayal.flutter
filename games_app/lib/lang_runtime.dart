import 'dart:async';
import 'dart:convert';

import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// ترجمة نصوص اللعبة التي لا مفتاح لها في _i18n.json (بُنيت وقت اللعب أو جاءت من خادم) على الجهاز بلا إنترنت
/// (نماذج Google ML Kit تُنزَّل مرة لكل لغة)، المصدر إنجليزي. تُخزَّن النتائج في الذاكرة طوال الجلسة.
class RuntimeTranslator {
  RuntimeTranslator._();
  static final Map<String, OnDeviceTranslator> _tr = {};
  static final Map<String, String?> _cache = {}; // "lang|key" -> ترجمة أو null
  static final Set<String> _noModel = {};
  static final _manager = OnDeviceTranslatorModelManager();
  static int _served = 0;

  static TranslateLanguage? _lang(String code) {
    final c = code == 'zh-CN' ? 'zh' : code;
    for (final l in TranslateLanguage.values) {
      if (l.bcp47Code == c) return l;
    }
    return null;
  }

  static bool supports(String lang) => lang != 'en' && _lang(lang) != null;

  static Future<bool> _ensureModels(String lang) async {
    if (_noModel.contains(lang)) return false;
    try {
      for (final code in ['en', _lang(lang)!.bcp47Code]) {
        if (!await _manager.isModelDownloaded(code)) {
          final ok = await _manager.downloadModel(code, isWifiRequired: false).timeout(const Duration(seconds: 90));
          if (!ok) {
            _noModel.add(lang);
            return false;
          }
        }
      }
      return true;
    } catch (_) {
      _noModel.add(lang);
      return false;
    }
  }

  /// [keys]: مفاتيح مطبَّعة فيها {#} للأرقام. ترجع {مفتاح: قيمة بـ{1}{2}…} للناجح فقط.
  static Future<Map<String, String>> translate(String lang, List<String> keys) async {
    final out = <String, String>{};
    final target = _lang(lang);
    if (target == null || lang == 'en' || keys.isEmpty) return out;
    if (_served > 1500) return out; // سقف أمان للجلسة (القناة مكشوفة لشيفرة اللعبة)
    if (!await _ensureModels(lang)) return out;
    final t = _tr.putIfAbsent(lang, () => OnDeviceTranslator(sourceLanguage: TranslateLanguage.english, targetLanguage: target));
    for (final key in keys) {
      if (key.length > 200) continue;
      final ck = '$lang|$key';
      if (_cache.containsKey(ck)) {
        final v = _cache[ck];
        if (v != null) out[key] = v;
        continue;
      }
      _served++;
      var n = 0;
      final src = key.replaceAllMapped('{#}', (_) => '{${++n}}');
      String? dst;
      try {
        final r = (await t.translateText(src)).replaceAllMapped(RegExp(r'\{\s*(\d+)\s*\}'), (m) => '{${m[1]}}');
        final ok = RegExp(r'\{\d+\}').allMatches(r).length == n && List.generate(n, (i) => i + 1).every((i) => '{$i}'.allMatches(r).length == 1);
        if (ok && r.trim().isNotEmpty && r.trim() != src.trim()) dst = r;
      } catch (_) {}
      _cache[ck] = dst;
      if (dst != null) out[key] = dst;
    }
    return out;
  }

  /// يحلّل رسالة القناة (قائمة نصوص JSON) بحذر: القناة تستقبلها من شيفرة اللعبة.
  static List<String> parse(String message) {
    try {
      final j = jsonDecode(message);
      if (j is! List) return const [];
      return [for (final x in j.take(30)) if (x is String && x.length <= 200) x];
    } catch (_) {
      return const [];
    }
  }
}
