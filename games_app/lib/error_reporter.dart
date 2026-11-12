import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'config.dart';

/// سجل أخطاء مجهول: يلتقط الأخطاء غير المعالجة ويرسل ملخصاً صغيراً إلى Worker الإحصاءات
/// ليظهر في تبويب «الأخطاء» بتطبيق المتحكم. لا اسم ولا بريد ولا موقع ولا معرّف إعلانات.
/// يُرسَل: نوع الخطأ ورسالته (مقصوصة ومنظَّفة من الروابط والبريد) وأول أسطر مكان الوقوع، إصدار التطبيق،
/// طراز الجهاز وإصدار أندرويد، رقم اللعبة المفتوحة، والمعرّف العشوائي نفسه الذي يستعمله عدّاد الأجهزة.
/// لا يعمل في وضع التطوير ولا إن كان `Config.statsUrl` فارغاً. فشل الإرسال لا يؤثر على التطبيق إطلاقاً.
class ErrorReporter {
  ErrorReporter._();

  static const _kQueue = 'err_queue';
  static const _kDay = 'err_day';
  static const _kCount = 'err_count';
  static const _kSeen = 'err_seen';
  static const _dayCap = 10; // أقصى بلاغات لهذا الجهاز في اليوم
  static const _queueCap = 20; // أقصى ما يُحفظ بانتظار الإرسال
  static bool _inside = false; // لا نبلّغ عن أخطائنا نحن (منعاً للحلقات)
  static bool _flushing = false;

  /// يُستدعى مرة واحدة في main() بعد ensureInitialized.
  static void install() {
    final prev = FlutterError.onError;
    FlutterError.onError = (details) {
      if (prev != null) {
        prev(details); // يبقى السلوك الأصلي (طباعة الخطأ)
      } else {
        FlutterError.presentError(details);
      }
      report(details.exception, details.stack, fatal: false);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, fatal: true); // استثناء غير ملتقَط خارج إطار Flutter
      return true;
    };
  }

  // أخطاء الشبكة المعتادة ليست عيوباً في التطبيق: لا نملأ السجل بها
  static bool _noise(Object e) {
    final t = e.runtimeType.toString();
    if (e is SocketException || e is TimeoutException || e is HandshakeException || e is HttpException) return true;
    return t.contains('ClientException') || t.contains('NetworkImageLoadException') || t.contains('TlsException');
  }

  static String _clean(String s, int max) {
    // الرابط الكامل (قد يحوي رمزاً أو بريداً) يُختصر إلى اسم الموقع فقط
    var t = s.replaceAllMapped(RegExp(r'https?://([^/\s]+)\S*'), (m) => m.group(1) ?? '');
    t = t.replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'), '<email>');
    t = t.replaceAll(RegExp(r'file:///\S*/'), '').replaceAll(RegExp(r'/data/(user|data)/\S*/'), '');
    return t.length > max ? t.substring(0, max) : t;
  }

  static String _stack(StackTrace? st) {
    if (st == null) return '';
    final lines = st.toString().split('\n').where((l) => l.trim().isNotEmpty).take(8).map((l) => _clean(l.trim(), 160));
    return lines.join('\n');
  }

  static String _hash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h.toRadixString(36);
  }

  static Future<void> report(Object error, StackTrace? stack, {bool fatal = false}) async {
    if (_inside || kDebugMode || Config.statsUrl.trim().isEmpty || _noise(error)) return;
    _inside = true;
    try {
      final type = _clean(error.runtimeType.toString(), 80);
      final msg = _clean('$error', 300);
      final st = _stack(stack);
      final fp = _hash('$type|${st.split('\n').take(3).join('|')}');
      final prefs = await SharedPreferences.getInstance();
      final day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      if (prefs.getString(_kDay) != day) {
        await prefs.setString(_kDay, day);
        await prefs.setInt(_kCount, 0);
        await prefs.setStringList(_kSeen, []);
      }
      final seen = prefs.getStringList(_kSeen) ?? [];
      final count = prefs.getInt(_kCount) ?? 0;
      if (seen.contains(fp) || count >= _dayCap) return; // نفس الخطأ مرة واحدة في اليوم
      await prefs.setStringList(_kSeen, [...seen, fp]);
      await prefs.setInt(_kCount, count + 1);

      var ver = '', android = '', model = '';
      try {
        ver = (await PackageInfo.fromPlatform()).version;
      } catch (_) {}
      try {
        final a = await DeviceInfoPlugin().androidInfo;
        android = '${a.version.release} (SDK ${a.version.sdkInt})';
        model = '${a.manufacturer} ${a.model}';
      } catch (_) {}
      final g = AppState.currentGame;
      final entry = <String, dynamic>{
        'app': 'games',
        'v': ver,
        'type': type,
        'msg': msg,
        'stack': st,
        'ctx': _clean('${g['id'] ?? ''}', 80),
        'android': _clean(android, 40),
        'model': _clean(model, 60),
        'fatal': fatal,
      };
      final raw = prefs.getStringList(_kQueue) ?? [];
      raw.add(jsonEncode(entry));
      while (raw.length > _queueCap) {
        raw.removeAt(0);
      }
      await prefs.setStringList(_kQueue, raw);
    } catch (_) {
      // لا شيء: السجل ثانوي
    } finally {
      _inside = false;
    }
    unawaited(flush());
  }

  /// يرسل ما في الطابور (يُستدعى بعد كل بلاغ وعند بدء التطبيق). ما فشل إرساله يبقى للمحاولة التالية.
  static Future<void> flush() async {
    var base = Config.statsUrl.trim();
    if (base.isEmpty || _flushing || kDebugMode) return;
    _flushing = true;
    try {
      if (base.endsWith('/')) base = base.substring(0, base.length - 1);
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString('dev_id') ?? '';
      if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) return; // المعرّف يُنشأ في DevicePing؛ ننتظر أول تشغيل ناجح
      final raw = List<String>.from(prefs.getStringList(_kQueue) ?? []);
      final left = <String>[];
      for (var i = 0; i < raw.length; i++) {
        try {
          final body = jsonDecode(raw[i]) as Map<String, dynamic>;
          body['id'] = id;
          final res = await http
              .post(Uri.parse('$base/err'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
              .timeout(const Duration(seconds: 8));
          if (res.statusCode == 204 || res.statusCode == 200 || res.statusCode == 400) continue; // 400 = بلاغ مرفوض نهائياً
          left.add(raw[i]);
        } catch (_) {
          left.addAll(raw.sublist(i)); // لا إنترنت: نحتفظ بالباقي
          break;
        }
      }
      await prefs.setStringList(_kQueue, left);
    } catch (_) {
    } finally {
      _flushing = false;
    }
  }
}
