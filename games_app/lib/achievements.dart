import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';

import 'colors.dart';
import 'favorites.dart';
import 'l10n.dart';
import 'nav.dart';
import 'play_stats.dart';

class Ach {
  final String id;
  final String title;
  final String desc;
  final int Function(PlayStats s, int favs) value;
  final int target;
  const Ach(this.id, this.title, this.desc, this.value, this.target);
}

final List<Ach> kAchievements = [
  Ach('first', 'أول لعبة', 'افتح أي لعبة', (s, f) => s.gamesPlayed, 1),
  Ach('g5', 'مستكشف', 'جرّب 5 ألعاب مختلفة', (s, f) => s.gamesPlayed, 5),
  Ach('g15', 'هاوي ألعاب', 'جرّب 15 لعبة مختلفة', (s, f) => s.gamesPlayed, 15),
  Ach('g30', 'خبير الألعاب', 'جرّب 30 لعبة مختلفة', (s, f) => s.gamesPlayed, 30),
  Ach('t60', 'ساعة لعب', 'العب ساعة إجمالاً', (s, f) => s.totalSeconds ~/ 60, 60),
  Ach('t600', 'مدمن ألعاب', 'العب 10 ساعات إجمالاً', (s, f) => s.totalSeconds ~/ 60, 600),
  Ach('s3', 'ثلاثة أيام', 'العب 3 أيام متتالية', (s, f) => s.bestStreak, 3),
  Ach('s7', 'أسبوع كامل', 'العب 7 أيام متتالية', (s, f) => s.bestStreak, 7),
  Ach('s30', 'شهر من المتعة', 'العب 30 يوماً متتالياً', (s, f) => s.bestStreak, 30),
  Ach('n25', 'عودة دائمة', 'افتح 25 جلسة لعب', (s, f) => s.sessions, 25),
  Ach('f5', 'جامع المفضلة', 'أضف 5 ألعاب إلى المفضلة', (s, f) => f, 5),
];

/// يكتشف الإنجازات الجديدة ويعرض إشعاراً صغيراً فوق الشاشة (محلي بالكامل).
class Achievements {
  static const _key = 'ach_unlocked';
  static bool _ready = false;
  static bool _busy = false;
  static final List<Ach> _queue = [];
  static bool _showing = false;

  static Set<String> _done() {
    final favs = Favorites.instance.ids.length;
    return {for (final a in kAchievements) if (a.value(PlayStats.instance, favs) >= a.target) a.id};
  }

  /// يُستدعى مرة عند الإقلاع. المفتوح مسبقاً يُسجَّل بصمت فلا يُزعج اللاعب القديم.
  static void init() {
    Future.delayed(const Duration(seconds: 3), () async {
      try {
        final p = await SharedPreferences.getInstance();
        if (p.getStringList(_key) == null) await p.setStringList(_key, _done().toList());
      } catch (_) {}
      _ready = true;
    });
    Favorites.instance.addListener(check);
  }

  static Future<void> check() async {
    if (!_ready || _busy) return;
    _busy = true;
    try {
      final p = await SharedPreferences.getInstance();
      final saved = (p.getStringList(_key) ?? const <String>[]).toSet();
      final done = _done();
      final fresh = kAchievements.where((a) => done.contains(a.id) && !saved.contains(a.id)).toList();
      if (fresh.isEmpty) return;
      await p.setStringList(_key, {...saved, ...done}.toList());
      _queue.addAll(fresh);
      _next();
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  static void _next() {
    if (_showing || _queue.isEmpty) return;
    final overlay = Nav.navKey.currentState?.overlay;
    if (overlay == null) {
      _queue.clear();
      return;
    }
    _showing = true;
    final a = _queue.removeAt(0);
    late OverlayEntry e;
    e = OverlayEntry(builder: (_) => _Toast(a));
    overlay.insert(e);
    Future.delayed(const Duration(milliseconds: 3600), () {
      try {
        e.remove();
      } catch (_) {}
      _showing = false;
      _next();
    });
  }
}

class _Toast extends StatelessWidget {
  final Ach a;
  const _Toast(this.a);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 14,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 350),
          builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * -20), child: child)),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xF2230A33),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.yellowLabel, width: 1.5),
              ),
              child: Row(children: [
                const Icon(Icons.military_tech, color: AppColors.yellowLabel, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    const Text('إنجاز جديد', style: TextStyle(fontSize: 12, color: AppColors.yellowLabel, fontWeight: FontWeight.w700)),
                    Text(a.title, style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w800)),
                    Text(a.desc, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
