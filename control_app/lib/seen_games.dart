import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// علامة «جديدة / معادة» على الألعاب التي لم تُفتح بعد استيرادها.
/// الاستيراد يكتب في سجل اللعبة `imported_at` (أول استيراد) و`reimported_at` (كل إعادة استيراد)،
/// ونحفظ هنا على هذا الجهاز آخر قيمة فتحتَها لكل لعبة. إن اختلفت القيمة ظهرت العلامة حتى تفتح اللعبة.
/// ألعاب قديمة بلا هذين الحقلين لا علامة لها.
class SeenGames {
  SeenGames._();

  static const _k = 'seen_games';
  static Map<String, String> _m = {};
  static bool ready = false;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_k);
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw);
        if (j is Map) _m = {for (final e in j.entries) '${e.key}': '${e.value}'};
      }
    } catch (_) {}
    ready = true;
  }

  static String _sig(Map g) => '${g['reimported_at'] ?? g['imported_at'] ?? ''}';

  /// نص العلامة، أو null إن لا علامة (فُتحت أو لا تاريخ لها).
  static String? badge(Map g) {
    if (!ready) return null;
    final s = _sig(g);
    if (s.isEmpty || _m['${g['id']}'] == s) return null;
    return g['reimported_at'] != null ? 'معادة الاستيراد' : 'جديدة';
  }

  static Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_k, jsonEncode(_m));
    } catch (_) {}
  }

  static Future<void> markSeen(Map g) async {
    final s = _sig(g);
    if (s.isEmpty || _m['${g['id']}'] == s) return;
    _m['${g['id']}'] = s;
    await _save();
  }

  static Future<void> markAll(Iterable<Map> gs) async {
    for (final g in gs) {
      final s = _sig(g);
      if (s.isNotEmpty) _m['${g['id']}'] = s;
    }
    await _save();
  }
}
