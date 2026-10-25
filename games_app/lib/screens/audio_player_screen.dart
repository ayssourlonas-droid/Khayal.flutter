import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/colors.dart';
import '../widgets/design.dart';
import '../widgets/glow_button.dart';

/// يقابل AudioPlayer.gd + PlaylistScreen.gd — مشغّل صوت محلي (bass.mp3).
class AudioPlayerScreen extends StatefulWidget {
  const AudioPlayerScreen({super.key});

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> with SingleTickerProviderStateMixin {
  static const _fade = Duration(milliseconds: 400);
  static const _seekFade = Duration(milliseconds: 100);

  final AudioPlayer _player = AudioPlayer();
  final List<String> _playlist = ['audio/bass.mp3']; // add_to_playlist("bass.mp3")
  int _index = 0;
  bool _isPlaying = false;
  bool _started = false; // بدأ التشغيل مرة (للتمييز بين play/resume)
  int _mode = 0; // 0 ترتيبي، 1 تكرار، 2 عشوائي
  double _volume = 1.0;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _seeking = false;
  double _seekValue = 0;
  String _song = '';
  Timer? _fadeTimer;

  late final Ticker _ticker;
  final ValueNotifier<double> _t = ValueNotifier(0);

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _t.value = d.inMicroseconds / 1e6)..start();
    _player.setReleaseMode(ReleaseMode.stop);
    _subs.add(_player.onPositionChanged.listen((p) {
      if (!_seeking && mounted) setState(() => _pos = p);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _dur = d);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) => _onFinished()));
    _loadTrack(0);
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  String _name(String path) {
    final f = path.split('/').last;
    final dot = f.lastIndexOf('.');
    return dot > 0 ? f.substring(0, dot) : f;
  }

  Future<void> _loadTrack(int i) async {
    if (_playlist.isEmpty) {
      setState(() => _song = 'القائمة فارغة - أضف ملفات صوتية');
      return;
    }
    _index = i.clamp(0, _playlist.length - 1).toInt();
    try {
      await _player.setSource(AssetSource(_playlist[_index]));
      final d = await _player.getDuration();
      setState(() {
        _dur = d ?? Duration.zero;
        _pos = Duration.zero;
        _song = '🎵 ${_name(_playlist[_index])}';
        _started = false;
      });
    } catch (_) {
      setState(() => _song = '⚠️ تعذر تحميل الملف');
    }
  }

  /// تلاشٍ خطي للصوت (FADE_DURATION = 0.4 ث).
  void _fadeTo(double target, {Duration d = _fade, VoidCallback? done}) {
    _fadeTimer?.cancel();
    final start = _cur;
    const steps = 12;
    var n = 0;
    _fadeTimer = Timer.periodic(Duration(milliseconds: (d.inMilliseconds / steps).round()), (t) {
      n++;
      _cur = start + (target - start) * (n / steps);
      _player.setVolume(_cur.clamp(0.0, 1.0));
      if (n >= steps) {
        t.cancel();
        _fadeTimer = null;
        done?.call();
      }
    });
  }

  double _cur = 1.0;

  Future<void> _playPause() async {
    if (_playlist.isEmpty) return;
    if (_isPlaying) {
      _fadeTo(0, done: () => _player.pause());
      setState(() => _isPlaying = false);
    } else if (_started) {
      _cur = 0;
      await _player.setVolume(0);
      await _player.resume();
      _fadeTo(_volume);
      setState(() => _isPlaying = true);
    } else {
      _cur = 0;
      await _player.setVolume(0);
      await _player.resume();
      _started = true;
      _fadeTo(_volume);
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _stop() async {
    final p = _pos;
    _fadeTo(0, done: () async {
      await _player.stop();
      await _player.setVolume(_volume);
      _cur = _volume;
    });
    setState(() {
      _isPlaying = false;
      _started = false;
      _pos = p;
    });
  }

  Future<void> _step(int dir) async {
    if (_playlist.isEmpty) return;
    final was = _isPlaying;
    var n = _index + dir;
    if (n < 0) n = _playlist.length - 1; // التفاف
    if (n >= _playlist.length) n = 0;
    await _loadTrack(n);
    if (was) {
      _cur = 0;
      await _player.setVolume(0);
      await _player.resume();
      _started = true;
      _fadeTo(_volume);
      setState(() => _isPlaying = true);
    }
  }

  void _onFinished() {
    setState(() {
      _isPlaying = false;
      _pos = Duration.zero;
    });
    if (_mode == 1) {
      _restartCurrent();
    } else if (_mode == 2 && _playlist.length > 1) {
      // عشوائي: مقطع مختلف عن الحالي (في الأصل كان الوضع غير مفعّل فعلياً)
      var n = _index;
      while (n == _index) {
        n = math.Random().nextInt(_playlist.length);
      }
      _loadTrack(n).then((_) => _restartCurrent());
    } else if (_index < _playlist.length - 1) {
      _isPlaying = true; // يتابع بالمقطع التالي
      _step(1);
    }
  }

  Future<void> _restartCurrent() async {
    _cur = 0;
    await _player.setVolume(0);
    await _player.seek(Duration.zero);
    await _player.resume();
    _started = true;
    _fadeTo(_volume);
    if (mounted) setState(() => _isPlaying = true);
  }

  Future<void> _seekTo(double percent) async {
    if (_dur == Duration.zero) return;
    final target = Duration(milliseconds: (_dur.inMilliseconds * percent / 100).round());
    _fadeTo(0, d: _seekFade, done: () async {
      await _player.seek(target);
      if (mounted) setState(() => _pos = target);
      _fadeTo(_volume, d: _seekFade);
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _openPlaylist() async {
    final r = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'playlist',
      barrierColor: Colors.black54,
      pageBuilder: (ctx, _, __) => Design(
        builder: (c, h) => Center(child: _PlaylistPanel(playlist: _playlist, current: _index)),
      ),
    );
    if (r != null) {
      var i = _playlist.indexOf(r);
      if (i < 0) {
        _playlist.add(r);
        i = _playlist.length - 1;
      }
      await _loadTrack(i);
      _cur = 0;
      await _player.setVolume(0);
      await _player.resume();
      _started = true;
      _fadeTo(_volume);
      setState(() => _isPlaying = true);
    }
  }

  static const _modeIcons = [
    'assets/images/a1l.webp', // ترتيبي
    'assets/images/a1m.webp', // تكرار
    'assets/images/a1n.webp', // عشوائي
  ];

  @override
  Widget build(BuildContext context) {
    final seekPercent = _seeking
        ? _seekValue
        : (_dur.inMilliseconds > 0 ? (_pos.inMilliseconds / _dur.inMilliseconds * 100).clamp(0.0, 100.0) : 0.0);
    return Scaffold(
      body: Design(
        builder: (ctx, h) => Stack(
          children: [
            // الخلفية 1920x2220 بحركة top_page_movement
            Positioned(
              left: -345,
              top: -149,
              width: 1920,
              height: 2220,
              child: AnimatedBuilder(
                animation: _t,
                builder: (_, child) => Transform.translate(
                  offset: Offset(math.sin(_t.value * 0.5) * 0.01 * 1920, math.cos(_t.value * 0.5) * 0.01 * 2220),
                  child: child,
                ),
                child: GodotGradientBox(loadingGradient),
              ),
            ),
            // زر الإغلاق (إيقاف + عودة)
            Positioned(
              right: 25,
              top: 25,
              child: GlowButton(
                onTap: () {
                  _stop();
                  Navigator.of(ctx).maybePop();
                },
                child: SizedBox(width: 200, height: 100, child: Image.asset('assets/images/a1c.webp', fit: BoxFit.contain)),
              ),
            ),
            // المشغّل
            Positioned(
              left: 40,
              right: 40,
              top: 200,
              bottom: 200,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Center(
                      child: SizedBox(
                        width: 800,
                        height: 800,
                        child: Stack(
                          children: [
                            Positioned.fill(child: GodotGradientBox(loadingGradient)),
                            Positioned.fill(child: GodotGradientBox(audioCoverGradient)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('🎵 مشغل الصوت',
                      style: TextStyle(fontSize: 28, color: Colors.white, decoration: TextDecoration.none)),
                  const SizedBox(height: 20),
                  Text(_song.isEmpty ? 'لا يوجد ملف صوتي محدد' : _song,
                      style: const TextStyle(
                          fontSize: 16, color: Color.fromRGBO(179, 230, 255, 1), decoration: TextDecoration.none)),
                  const SizedBox(height: 20),
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 10,
                      activeTrackColor: AppColors.popupBorder,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      min: 0,
                      max: 100,
                      value: seekPercent.toDouble(),
                      onChangeStart: (_) => setState(() => _seeking = true),
                      onChanged: (v) => setState(() => _seekValue = v),
                      onChangeEnd: (v) {
                        setState(() => _seeking = false);
                        _seekTo(v);
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    textDirection: TextDirection.ltr,
                    children: [
                      Expanded(
                        child: Text(_fmt(_pos),
                            style: const TextStyle(
                                fontSize: 35, color: Color.fromRGBO(204, 204, 204, 1), decoration: TextDecoration.none)),
                      ),
                      Text(_fmt(_dur),
                          style: const TextStyle(
                              fontSize: 35, color: Color.fromRGBO(204, 204, 204, 1), decoration: TextDecoration.none)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    textDirection: TextDirection.ltr,
                    children: [
                      _ctl(
                          Transform.flip(flipX: true, child: Image.asset('assets/images/a1f.webp', fit: BoxFit.contain)),
                          130, 100, () => _step(-1)),
                      const SizedBox(width: 15),
                      _ctl(Image.asset(_isPlaying ? 'assets/images/a1e.webp' : 'assets/images/a1f.webp', fit: BoxFit.contain),
                          200, 200, _playPause),
                      const SizedBox(width: 15),
                      _ctl(Image.asset('assets/images/a1f.webp', fit: BoxFit.contain), 130, 100, () => _step(1)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: _ctl(Image.asset(_modeIcons[_mode], fit: BoxFit.contain), 90, 60,
                        () => setState(() => _mode = (_mode + 1) % 3)),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: _openPlaylist,
                    child: const Text('📋 القائمة',
                        style: TextStyle(fontSize: 16, color: Colors.white, decoration: TextDecoration.none)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctl(Widget icon, double w, double h, VoidCallback onTap) =>
      GlowButton(onTap: onTap, child: SizedBox(width: w, height: h, child: icon));
}

class _PlaylistPanel extends StatelessWidget {
  final List<String> playlist;
  final int current;
  const _PlaylistPanel({required this.playlist, required this.current});

  String _name(String path) {
    final f = path.split('/').last;
    final dot = f.lastIndexOf('.');
    return dot > 0 ? f.substring(0, dot) : f;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 900,
        height: 900,
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.96),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: AppColors.popupBorder, width: 5),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('📋 القائمة',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 40, color: Colors.white)),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Text('✕', style: TextStyle(fontSize: 44, color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: playlist.isEmpty
                  ? const Center(
                      child: Text('القائمة فارغة - أضف ملفات صوتية',
                          style: TextStyle(fontSize: 30, color: Colors.white70)))
                  : ListView.builder(
                      itemCount: playlist.length,
                      itemBuilder: (_, i) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).pop(playlist[i]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '${i == current ? '▶ ' : '🎵 '}${_name(playlist[i])}',
                              style: TextStyle(
                                fontSize: 32,
                                color: i == current ? const Color.fromRGBO(153, 204, 255, 1) : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
