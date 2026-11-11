import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

/// يقابل PlayerPoints.gd — نقاط اللاعب (تُحفظ بين الجلسات).
class PlayerPoints extends ChangeNotifier {
  PlayerPoints._();
  static final PlayerPoints instance = PlayerPoints._();

  static const _key = 'player_points';
  static const _dayKey = 'points_day';

  /// تاريخ اليوم بتوقيت الجهاز بصيغة yyyy-mm-dd.
  static String _today() {
    final d = DateTime.now();
    String t(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${t(d.month)}-${t(d.day)}';
  }
  int _points = 0;
  int get points => _points;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getInt(_key);
      final today = _today();
      final lastDay = p.getString(_dayKey);
      if (saved == null) {
        // أول تشغيل بعد التثبيت: هدية ترحيبية تُمنح مرة واحدة فقط (ولا نقاط يومية في اليوم نفسه)
        _points = Config.welcomePoints;
        await p.setString(_dayKey, today);
      } else {
        _points = saved;
        // نقاط يومية: مرة واحدة لكل يوم جديد. نقارن النص (yyyy-mm-dd) فلا يكفي إرجاع ساعة الهاتف للحصول عليها مجدداً.
        if (lastDay == null || today.compareTo(lastDay) > 0) {
          _points += Config.dailyPoints;
          await p.setString(_dayKey, today);
        }
      }
      await p.setInt(_key, _points);
    } catch (_) {
      _points = 0;
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_key, _points);
    } catch (_) {}
  }

  void addPoints([int n = 1]) {
    if (n <= 0) return;
    _points += n;
    _save();
    notifyListeners();
  }

  /// يخصم نقاطاً؛ يرجع false إن لم يكف الرصيد.
  bool usePoint([int n = 1]) {
    if (_points < n) return false;
    _points -= n;
    _save();
    notifyListeners();
    return true;
  }
}
