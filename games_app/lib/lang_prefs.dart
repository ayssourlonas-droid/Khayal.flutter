import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n_loader.dart';
import 'lang_runtime.dart';

/// لغة نصوص الألعاب: تلقائي (لغة الجهاز) | بلا ترجمة | لغة محددة.
/// الترجمة نفسها في ملف `_i18n.json` بجانب كل لعبة (يبنيه خط الاستيراد)، ويُحقن سكربت يستبدل النصوص وقت اللعب.
class LangPrefs {
  LangPrefs._();
  static final LangPrefs instance = LangPrefs._();

  static const auto = 'auto';
  static const off = 'off';
  static const _prefKey = 'game_lang';

  /// اللغات المدعومة (رموزها مطابقة لما يكتبه الخط في _i18n.json): رمز ← اسمها بلغتها.
  static const Map<String, String> names = {
    'ar': 'العربية', 'en': 'English', 'fr': 'Français', 'es': 'Español', 'pt': 'Português', 'de': 'Deutsch',
    'it': 'Italiano', 'ru': 'Русский', 'tr': 'Türkçe', 'zh-CN': '中文', 'ja': '日本語', 'ko': '한국어',
    'hi': 'हिन्दी', 'id': 'Bahasa Indonesia', 'fa': 'فارسی', 'ur': 'اردو', 'bn': 'বাংলা', 'vi': 'Tiếng Việt',
    'th': 'ไทย', 'pl': 'Polski', 'nl': 'Nederlands', 'uk': 'Українська', 'ms': 'Bahasa Melayu',
  };

  /// قابل للاستماع ليتحدّث صف الإعدادات مباشرة.
  final ValueNotifier<String> gameLang = ValueNotifier<String>(auto);

  Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(_prefKey) ?? auto;
      gameLang.value = (v == auto || v == off || names.containsKey(v)) ? v : auto;
    } catch (_) {}
  }

  Future<void> set(String v) async {
    gameLang.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefKey, v);
    } catch (_) {}
  }

  /// النص الظاهر في الإعدادات للقيمة الحالية.
  String label(String v) {
    if (v == auto) return 'تلقائي (لغة الجهاز)';
    if (v == off) return 'الأصلية بلا ترجمة';
    return names[v] ?? v;
  }

  /// اللغة الفعلية للحقن، أو null إن لا ترجمة (مُعطَّلة أو لغة الجهاز غير مدعومة).
  String? resolved() {
    final v = gameLang.value;
    if (v == off) return null;
    if (v != auto) return v;
    final l = ui.PlatformDispatcher.instance.locale;
    final code = l.languageCode.toLowerCase();
    if (code == 'zh') return 'zh-CN';
    if (code == 'in') return 'id'; // الرمز القديم للإندونيسية
    return names.containsKey(code) ? code : null;
  }
}

/// يجلب ملف ترجمة اللعبة ويبني سكربت الحقن للغة المختارة.
class I18nInjector {
  I18nInjector._();
  static final Map<String, Map<String, dynamic>?> _cache = {};

  static Future<Map<String, dynamic>?> _fetch(Uri u) async {
    final key = u.toString();
    if (!_cache.containsKey(key)) {
      Map<String, dynamic>? data;
      try {
        final r = await http.get(u).timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          final j = jsonDecode(utf8.decode(r.bodyBytes));
          if (j is Map<String, dynamic>) data = j;
        }
      } catch (_) {}
      _cache[key] = data; // نخزّن الفشل أيضاً كي لا نكرّر الطلب في كل تحميل صفحة
    }
    return _cache[key];
  }

  static void _merge(Map<String, String> into, dynamic strings, String lang) {
    if (strings is! Map) return;
    strings.forEach((k, v) {
      if (v is Map && v[lang] is String) into[k.toString()] = v[lang] as String;
    });
  }

  /// يرجع سكربتاً جاهزاً لـ runJavaScript، أو null (لا ترجمة).
  /// الترتيب: ملف اللعبة _i18n.json، ثم تصحيحات المالك _i18n_overrides.json (تغلب عليه)، ثم ترجمة وقت اللعب
  /// على الجهاز لما لا مفتاح له (تعمل حتى للعبة بلا ملف لغات، كالألعاب المستوردة قبل هذه الميزة).
  static Future<String?> scriptFor(String pageUrl) async {
    final lang = LangPrefs.instance.resolved();
    if (lang == null) return null;
    final base = Uri.tryParse(pageUrl);
    final u = base?.resolve('_i18n.json');
    if (u == null || u.scheme != 'https') return null;
    final map = <String, String>{};
    _merge(map, (await _fetch(u))?['strings'], lang);
    _merge(map, (await _fetch(base!.resolve('_i18n_overrides.json')))?['strings'], lang);
    final rt = RuntimeTranslator.supports(lang);
    if (map.isEmpty && !rt) return null;
    return '$kI18nLoaderJs(${jsonEncode({'lang': lang, 'map': map, 'rt': rt})});';
  }
}
