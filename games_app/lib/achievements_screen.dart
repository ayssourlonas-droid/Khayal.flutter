import 'package:flutter/material.dart' hide Text;

import 'achievements.dart';
import 'colors.dart';
import 'favorites.dart';
import 'l10n.dart';
import 'play_stats.dart';

String _fmt(int secs) {
  final h = secs ~/ 3600, m = (secs % 3600) ~/ 60;
  if (h > 0) return L10n.isAr ? '$h س $m د' : '${h}h ${m}m';
  if (m > 0) return L10n.isAr ? '$m د' : '${m}m';
  return L10n.isAr ? '${secs} ث' : '${secs}s';
}

/// إنجازات وإحصاءات اللاعب (محلية على الجهاز).
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  Widget _tile(String label, String value, IconData icon) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
              color: const Color(0x33B34DE6), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.popupBorder.withOpacity(0.6))),
          child: Column(children: [
            Icon(icon, color: AppColors.yellowLabel, size: 24),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = PlayStats.instance;
    return Scaffold(
      backgroundColor: AppColors.gameBg,
      appBar: AppBar(
        backgroundColor: AppColors.gameBg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('إنجازاتي', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([s, Favorites.instance, L10n.lang]),
        builder: (_, __) {
          final favs = Favorites.instance.ids.length;
          final top = s.top();
          final heavy = s.heavy();
          final done = kAchievements.where((a) => a.value(s, favs) >= a.target).length;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
            Row(children: [
              _tile('زمن اللعب', _fmt(s.totalSeconds), Icons.timer),
              const SizedBox(width: 8),
              _tile('ألعاب جرّبتها', '${s.gamesPlayed}', Icons.sports_esports),
              const SizedBox(width: 8),
              _tile('أيام متتالية', '${s.streak}', Icons.local_fire_department),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _tile('أفضل تتابع', '${s.bestStreak}', Icons.emoji_events),
              const SizedBox(width: 8),
              _tile('الجلسات', '${s.sessions}', Icons.play_circle),
              const SizedBox(width: 8),
              _tile('الإنجازات', '$done/${kAchievements.length}', Icons.military_tech),
            ]),
            if (top.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('الأكثر لعباً', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.yellowLabel)),
              const SizedBox(height: 6),
              for (final t in top)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text(t.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14.5))),
                    Text(_fmt(t.$3), style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
                  ]),
                ),
            ],
            if (heavy.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('ألعاب ثقيلة على جهازك', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.yellowLabel)),
              const SizedBox(height: 2),
              const Text('متوسط الإطارات في الثانية أثناء لعبك (أقل من 40 يعني بطئاً).', style: TextStyle(fontSize: 11.5, color: Colors.white54)),
              const SizedBox(height: 6),
              for (final h in heavy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text(h.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14.5))),
                    Text('${h.$3.round()} fps', style: TextStyle(color: h.$3 < 25 ? const Color(0xFFFF6B6B) : const Color(0xFFFFC857), fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ]),
                ),
            ],
            const SizedBox(height: 18),
            const Text('الإنجازات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.yellowLabel)),
            const SizedBox(height: 8),
            for (final a in kAchievements)
              Builder(builder: (_) {
                final v = a.value(s, favs);
                final ok = v >= a.target;
                final p = (v / a.target).clamp(0.0, 1.0);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ok ? const Color(0x3300C853) : const Color(0x22FFFFFF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ok ? const Color(0xFF3DDC84) : Colors.white24),
                  ),
                  child: Row(children: [
                    Icon(ok ? Icons.check_circle : Icons.lock_outline, color: ok ? const Color(0xFF3DDC84) : Colors.white38, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                        Text(a.desc, style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
                        if (!ok) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(value: p, minHeight: 6, backgroundColor: Colors.white12, color: AppColors.popupBorder),
                          ),
                        ],
                      ]),
                    ),
                  ]),
                );
              }),
            const SizedBox(height: 6),
            const Text('تُحفظ هذه البيانات على جهازك فقط.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: Colors.white38)),
          ]);
        },
      ),
    );
  }
}
