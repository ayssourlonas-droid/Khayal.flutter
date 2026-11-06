/// يقابل GameLibrary.gd — فحص سلامة بيانات اللعبة.
/// فحص الرخصة يتم في تطبيق «متحكم» قبل الاعتماد، فلا يكرّره هذا التطبيق.
/// لا تظهر لعبة إلا إذا كان لها: رابط https + نوع مدعوم + مطوّر + رابط مصدر.
class GameLibrary {
  GameLibrary._();

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  /// نوع اللعبة: web (الافتراضي) أو pc (مستقبلاً: بث من الحاسوب).
  static String typeOf(Map<String, dynamic> game) {
    final t = (_map(game['details_scene'])['type'] ?? 'web').toString().trim();
    return t.isEmpty ? 'web' : t;
  }

  /// يرجع "" إذا كانت اللعبة سليمة، وإلا نص يشرح السبب.
  static String validate(Map<String, dynamic> game) {
    final d = _map(game['details_scene']);
    if (typeOf(game) != 'web') return 'نوع اللعبة غير مدعوم في هذا الإصدار';
    final playUrl = (d['play_url'] ?? '').toString().trim();
    if (!playUrl.startsWith('https://')) {
      return 'رابط التشغيل مفقود أو ليس https';
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
