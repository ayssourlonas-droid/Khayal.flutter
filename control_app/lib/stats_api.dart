import 'dart:convert';
import 'package:http/http.dart' as http;
import 'github.dart' show GhException;
import 'store.dart';

class PlayStat {
  final String slug;
  final int plays;
  PlayStat(this.slug, this.plays);
}

class DevDay {
  final String day;
  final int active;
  final int fresh;
  DevDay(this.day, this.active, this.fresh);
}

class VerCount {
  final String ver;
  final int n;
  VerCount(this.ver, this.n);
}

/// أرقام الأجهزة المجهولة: total = كل جهاز ظهر يوماً، active = أجهزة استُعملت خلال الفترة،
/// fresh = أجهزة ظهرت لأول مرة خلال الفترة.
class DeviceStats {
  final int total;
  final int active;
  final int fresh;
  final List<DevDay> daily;
  final List<VerCount> versions;
  DeviceStats(this.total, this.active, this.fresh, this.daily, this.versions);
}

class StatsData {
  final List<PlayStat> games;
  final DeviceStats? devices; // null إن لم يدعم الـWorker الأجهزة بعد
  StatsData(this.games, this.devices);
}

int _int(Object? v) => (v is num) ? v.toInt() : 0;

/// يقرأ إحصاءات اللعب والأجهزة من Worker (بلا أي بيانات شخصية).
class StatsApi {
  StatsApi._();

  static Future<List<PlayStat>> fetch(int days) async => (await fetchAll(days)).games;

  static Future<StatsData> fetchAll(int days) async {
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
    final games = [
      for (final e in list)
        if (e is Map) PlayStat('${e['slug']}', _int(e['plays']))
    ];
    DeviceStats? dev;
    final d = (j is Map) ? j['devices'] : null;
    if (d is Map) {
      final daily = [
        for (final e in (d['daily'] is List ? d['daily'] as List : []))
          if (e is Map) DevDay('${e['day']}', _int(e['active']), _int(e['new']))
      ];
      final vers = [
        for (final e in (d['versions'] is List ? d['versions'] as List : []))
          if (e is Map) VerCount('${e['ver']}', _int(e['n']))
      ];
      dev = DeviceStats(_int(d['total']), _int(d['active']), _int(d['new']), daily, vers);
    }
    return StatsData(games, dev);
  }
}
