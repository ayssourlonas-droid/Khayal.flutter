import 'dart:convert';
import 'package:http/http.dart' as http;
import 'github.dart' show GhException;
import 'store.dart';

class PlayStat {
  final String slug;
  final int plays;
  PlayStat(this.slug, this.plays);
}

/// يقرأ عدد مرات فتح كل لعبة من Worker (بلا أي بيانات شخصية).
class StatsApi {
  StatsApi._();

  static Future<List<PlayStat>> fetch(int days) async {
    var base = Store.statsUrl.trim();
    if (base.isEmpty || Store.statsToken.isEmpty) {
      throw GhException('أدخل رابط الإحصاء والرمز في الإعدادات أولاً.');
    }
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    final r = await http
        .get(Uri.parse('$base/stats?days=$days'), headers: {'Authorization': 'Bearer ${Store.statsToken}'})
        .timeout(const Duration(seconds: 30));
    if (r.statusCode == 401) throw GhException('الرمز غير صحيح (401).');
    if (r.statusCode == 501) throw GhException('لم تُربط قاعدة D1 بالـWorker بعد.');
    if (r.statusCode != 200) throw GhException('خطأ ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final list = (j is Map && j['games'] is List) ? j['games'] as List : [];
    return [
      for (final e in list)
        if (e is Map) PlayStat('${e['slug']}', (e['plays'] as num?)?.toInt() ?? 0)
    ];
  }
}
