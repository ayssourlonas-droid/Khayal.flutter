import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

/// عدّاد أجهزة مجهول: عند أول تشغيل يولّد التطبيق رقماً عشوائياً (32 خانة) ويحفظه على الهاتف،
/// ثم يرسله مرة واحدة في اليوم مع رقم إصدار التطبيق، فنعرف كم جهازاً مختلفاً يستعمل خيال.
/// لا اسم ولا بريد ولا معرّف إعلانات. يُمحى الرقم بحذف التطبيق أو مسح بياناته.
/// لا يؤثر على التشغيل إن فشل أو كان `Config.statsUrl` فارغاً.
class DevicePing {
  DevicePing._();

  static const _kId = 'dev_id';
  static const _kDay = 'dev_day';
  static final _hex32 = RegExp(r'^[0-9a-f]{32}$');
  static bool _busy = false;

  static Future<void> run() async {
    var base = Config.statsUrl.trim();
    if (base.isEmpty || _busy) return;
    _busy = true;
    try {
      if (base.endsWith('/')) base = base.substring(0, base.length - 1);
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_kId) ?? '';
      if (!_hex32.hasMatch(id)) {
        final r = Random.secure();
        id = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
        await prefs.setString(_kId, id);
      }
      // مرة واحدة في اليوم (بتوقيت UTC، مثل الخادم)
      final day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      if (prefs.getString(_kDay) == day) return;
      var ver = '';
      try {
        ver = (await PackageInfo.fromPlatform()).version;
      } catch (_) {}
      final res = await http
          .post(Uri.parse('$base/dev'),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode({'id': id, 'v': ver}))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 204 || res.statusCode == 200) {
        await prefs.setString(_kDay, day); // نسجّل النجاح فقط، فإن فشل الإرسال نعيد المحاولة في التشغيل التالي
      }
    } catch (_) {
      // الإحصاء ثانوي: نتجاهل أي خطأ
    } finally {
      _busy = false;
    }
  }
}
