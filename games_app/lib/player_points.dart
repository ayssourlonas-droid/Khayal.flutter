import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// يقابل PlayerPoints.gd — نقاط اللاعب (تُحفظ بين الجلسات).
class PlayerPoints extends ChangeNotifier {
  PlayerPoints._();
  static final PlayerPoints instance = PlayerPoints._();

  static const _key = 'player_points';
  int _points = 0;
  int get points => _points;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _points = p.getInt(_key) ?? 0;
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
