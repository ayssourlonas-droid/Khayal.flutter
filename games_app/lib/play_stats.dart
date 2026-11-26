import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// إحصاءات اللاعب المحلية: زمن اللعب، الألعاب المجرَّبة، عدد الجلسات، وأيام التتابع.
/// تُحفظ على الجهاز فقط ولا تُرسَل لأي خادم. الزمن يُوقَف تلقائياً حين يذهب التطبيق للخلفية.
class PlayStats extends ChangeNotifier with WidgetsBindingObserver {
  PlayStats._();
  static final PlayStats instance = PlayStats._();

  static const _key = 'play_stats_v1';
  static const _maxSession = 3 * 3600; // سقف أمان للجلسة الواحدة (ثوانٍ): ترك الهاتف والتطبيق مفتوحاً

  int totalSeconds = 0;
  int sessions = 0;
  int streak = 0;
  int bestStreak = 0;
  String lastDay = '';
  final Map<String, int> secondsById = {}; // معرّف اللعبة ← ثوانٍ
  final Map<String, String> titleById = {};
  final Map<String, List<int>> perfById = {}; // معرّف ← [إطارات، مللي ثانية، إطارات بطيئة]

  int get gamesPlayed => secondsById.length;

  Stopwatch? _sw;
  String? _activeId;
  bool _loaded = false;
  bool _observing = false;

  static String _day(DateTime d) {
    String t(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${t(d.month)}-${t(d.day)}';
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final j = jsonDecode(p.getString(_key) ?? '{}');
      if (j is Map) {
        totalSeconds = (j['t'] as num?)?.toInt() ?? 0;
        sessions = (j['s'] as num?)?.toInt() ?? 0;
        streak = (j['st'] as num?)?.toInt() ?? 0;
        bestStreak = (j['bs'] as num?)?.toInt() ?? 0;
        lastDay = (j['d'] ?? '').toString();
        (j['g'] is Map ? j['g'] as Map : {}).forEach((k, v) => secondsById[k.toString()] = (v as num).toInt());
        (j['pf'] is Map ? j['pf'] as Map : {}).forEach((k, v) {
          if (v is List && v.length >= 3) perfById[k.toString()] = [for (final x in v.take(3)) (x as num).toInt()];
        });
        (j['n'] is Map ? j['n'] as Map : {}).forEach((k, v) => titleById[k.toString()] = v.toString());
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _key,
          jsonEncode({'t': totalSeconds, 's': sessions, 'st': streak, 'bs': bestStreak, 'd': lastDay, 'g': secondsById, 'n': titleById, 'pf': perfById}));
    } catch (_) {}
  }

  /// بداية جلسة لعب. يُحتسب اليوم في التتابع بمجرد فتح لعبة.
  void startSession(String id, String title) {
    if (id.isEmpty) return;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    endSession(); // أي جلسة سابقة
    _activeId = id;
    _sw = Stopwatch()..start();
    sessions++;
    secondsById.putIfAbsent(id, () => 0);
    if (title.isNotEmpty) titleById[id] = title;
    _touchDay();
    _save();
    notifyListeners();
  }

  void _touchDay() {
    final now = DateTime.now();
    final today = _day(now);
    if (lastDay == today) return;
    // ساعة الجهاز رجعت للوراء: لا نغيّر التتابع
    if (lastDay.isNotEmpty && today.compareTo(lastDay) < 0) return;
    final yesterday = _day(now.subtract(const Duration(days: 1)));
    streak = (lastDay == yesterday) ? streak + 1 : 1;
    if (streak > bestStreak) bestStreak = streak;
    lastDay = today;
  }

  /// نهاية الجلسة: يُضاف الزمن المنقضي (مع السقف).
  void endSession() {
    final sw = _sw, id = _activeId;
    _sw = null;
    _activeId = null;
    if (sw == null || id == null) return;
    sw.stop();
    var s = sw.elapsed.inSeconds;
    if (s <= 0) return;
    if (s > _maxSession) s = _maxSession;
    totalSeconds += s;
    secondsById[id] = (secondsById[id] ?? 0) + s;
    _save();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final sw = _sw;
    if (sw == null) return;
    if (state == AppLifecycleState.resumed) {
      if (!sw.isRunning) sw.start();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      if (sw.isRunning) sw.stop();
    }
  }

  /// قياس الأداء: يُضاف ما جمعته صفحة اللعبة (إطارات، مللي ثانية، إطارات أبطأ من 50ms).
  void addPerf(String id, int frames, double ms, int slow) {
    if (id.isEmpty || frames <= 0 || ms <= 0) return;
    final p = perfById.putIfAbsent(id, () => [0, 0, 0]);
    p[0] += frames;
    p[1] += ms.round();
    p[2] += slow;
    _save();
    notifyListeners();
  }

  /// الألعاب الثقيلة: متوسط fps دون 40 مع 20 ثانية قياس على الأقل (معرّف، عنوان، fps).
  List<(String, String, double)> heavy([int n = 5]) {
    final l = <(String, String, double)>[];
    perfById.forEach((id, p) {
      if (p[1] < 20000) return;
      final fps = p[0] * 1000 / p[1];
      if (fps < 40) l.add((id, titleById[id] ?? '#$id', fps));
    });
    l.sort((a, b) => a.$3.compareTo(b.$3));
    return l.take(n).toList();
  }

  /// ألعاب الأكثر لعباً (معرّف، عنوان، ثوانٍ).
  List<(String, String, int)> top([int n = 5]) {
    final l = secondsById.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in l.take(n)) (e.key, titleById[e.key] ?? '#${e.key}', e.value)];
  }
}
