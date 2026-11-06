import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// أنواع المؤثرات الصوتية القصيرة (الملفات في assets/sfx/).
enum Sfx { tap, open, close, confirm, back, error }

/// مؤثرات الأزرار: مشغّل منخفض الكمون لكل نوع، وتفعيل/إيقاف محفوظ بين الجلسات.
/// الأصوات من Kenney Interface Sounds (CC0) — انظر assets/sfx/LICENSE.txt.
class SoundFx {
  SoundFx._();
  static final SoundFx instance = SoundFx._();

  /// قابل للاستماع ليتحدّث مفتاح الإعدادات مباشرة.
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
  final Map<Sfx, AudioPlayer> _players = {};
  static const _prefKey = 'sfx_enabled';

  Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      enabled.value = p.getBool(_prefKey) ?? true;
    } catch (_) {}
    for (final s in Sfx.values) {
      try {
        final pl = AudioPlayer();
        await pl.setPlayerMode(PlayerMode.lowLatency);
        // لا نسرق تركيز الصوت: المؤثر يختلط مع مشغّل الموسيقى وصوت الألعاب بدل إيقافهما
        await pl.setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
        await pl.setReleaseMode(ReleaseMode.stop);
        await pl.setVolume(0.6);
        _players[s] = pl;
      } catch (_) {}
    }
  }

  Future<void> setEnabled(bool v) async {
    enabled.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_prefKey, v);
    } catch (_) {}
  }

  /// يشغّل المؤثر من بدايته؛ أي خطأ يُتجاهل حتى لا يعطّل الواجهة.
  /// نوقف المشغّل أولاً: في الوضع منخفض الكمون قد لا يُعاد تشغيل الصوت بعد انتهائه
  /// إن لم يُوقَف صراحةً، فكان الصوت يُسمع مرة واحدة فقط.
  Future<void> play(Sfx s) async {
    if (!enabled.value) return;
    final pl = _players[s];
    if (pl == null) return;
    try {
      await pl.stop();
      await pl.play(AssetSource('sfx/${s.name}.ogg'));
    } catch (_) {}
  }
}
