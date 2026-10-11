import 'config.dart';

/// يقابل GameLibrary.gd — بوابة التحقق القانوني.
/// لا تظهر لعبة إلا إذا كان لها: رابط https + رخصة مسموحة + مطوّر + رابط مصدر.
class GameLibrary {
  GameLibrary._();

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  /// يرجع "" إذا كانت اللعبة سليمة، وإلا نص يشرح السبب.
  static String validate(Map<String, dynamic> game) {
    final d = _map(game['details_scene']);
    final playUrl = (d['play_url'] ?? '').toString().trim();
    if (!playUrl.startsWith('https://')) {
      return 'رابط التشغيل مفقود أو ليس https';
    }
    final lic = (d['license'] ?? '').toString().trim();
    if (!Config.allowedLicenses.contains(lic)) {
      return "رخصة غير مسموحة: '$lic'";
    }
    if ((d['developer'] ?? '').toString().trim().isEmpty) {
      return 'اسم المطوّر مفقود';
    }
    if (!(d['source_url'] ?? '').toString().trim().startsWith('http')) {
      return 'رابط المصدر مفقود';
    }
    return '';
  }

  static List<Map<String, dynamic>> filterValid(List<dynamic> list) {
    final out = <Map<String, dynamic>>[];
    for (final g in list) {
      if (g is! Map) continue;
      final game = Map<String, dynamic>.from(g);
      final why = validate(game);
      if (why.isEmpty) {
        out.add(game);
      } else {
        final title = _map(game['main_scene'])['title_ar'] ?? '?';
        // ignore: avoid_print
        print("⛔ [GameLibrary] استُبعدت اللعبة '$title' — $why");
      }
    }
    return out;
  }

  static String creditLine(Map<String, dynamic> game) {
    final d = _map(game['details_scene']);
    return 'المطوّر: ${d['developer'] ?? ''}  •  الرخصة: ${d['license'] ?? ''}';
  }
}
