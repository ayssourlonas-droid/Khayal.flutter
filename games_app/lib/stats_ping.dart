import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'config.dart';

/// عدّاد فتح الألعاب: يرسل اسم اللعبة فقط (بلا أي بيانات شخصية) إلى Worker مجاني على Cloudflare.
/// لا يؤثر على التشغيل إن فشل أو كان `Config.statsUrl` فارغاً.
class StatsPing {
  StatsPing._();

  static String _lastSlug = '';
  static DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<void> hit(String playUrl) async {
    var base = Config.statsUrl.trim();
    if (base.isEmpty) return;
    try {
      if (base.endsWith('/')) base = base.substring(0, base.length - 1);
      // رابط اللعبة: https://…/games/<slug>/
      final segs = Uri.parse(playUrl).pathSegments.where((s) => s.isNotEmpty).toList();
      final i = segs.indexOf('games');
      final slug = (i >= 0 && i + 1 < segs.length) ? segs[i + 1] : '';
      if (slug.isEmpty) return;
      // حماية من التكرار: نفس اللعبة خلال 20 ثانية تُحسب مرة واحدة
      final now = DateTime.now();
      if (slug == _lastSlug && now.difference(_lastAt).inSeconds < 20) return;
      _lastSlug = slug;
      _lastAt = now;
      // معرّف فريد لهذا الفتح: الـ Worker يتجاهل أي تكرار له
      final r = Random.secure();
      final id = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
      await http
          .post(Uri.parse('$base/hit'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'slug': slug, 'id': id}))
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // الإحصاء ثانوي: نتجاهل أي خطأ
    }
  }
}
