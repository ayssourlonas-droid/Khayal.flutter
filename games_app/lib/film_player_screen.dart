import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'l10n.dart';
import 'ads_manager.dart';
import 'film_data.dart';
import 'film_player_widgets.dart';

/// مشغّل الأفلام — يقابل VideoPlayer.gd + VideoUI.gd في جودوت، لكن بمحرك media_kit (libmpv/FFmpeg).
/// الميزات: روابط https مباشرة (MP4/MKV/WebM/HLS)، تحميل مسبق (buffering)، شريط تقديم بمنطقة آمنة،
/// نقر مزدوج للتقديم/الرجوع بمدة يختارها المستخدم، استئناف من آخر موضع، ترجمة خارجية أو مدمجة بمظهر قابل للتعديل،
/// مسارات صوت، سرعة التشغيل، وإبقاء الشاشة مضيئة. يُفتح بالعرض الأفقي ويعيد العمودي عند الخروج.
class FilmPlayerScreen extends StatefulWidget {
  const FilmPlayerScreen({super.key});

  @override
  State<FilmPlayerScreen> createState() => _FilmPlayerScreenState();
}

class _FilmPlayerScreenState extends State<FilmPlayerScreen> with WidgetsBindingObserver {
  late final Player _player = Player(configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024));
  late final VideoController _video = VideoController(_player);
  final List<StreamSubscription> _subs = [];

  late final Map<String, dynamic> _film = FilmState.currentFilm;
  late final String _id = FilmConfig.key(_film);
  late final String _url = FilmState.currentVideoUrl;

  Duration _pos = Duration.zero, _dur = Duration.zero, _buf = Duration.zero;
  bool _playing = false, _buffering = true, _ready = false, _controls = true, _ended = false;
  String? _error;

  // التقديم
  bool _dragging = false;
  double _dragRatio = 0;
  int _skip = 10;
  bool _fbVisible = false, _fbForward = true;
  Timer? _fbTimer, _hideTimer, _saveTimer;
  int _tapSide = 0; // -1 يسار، 1 يمين
  Offset? _lastTap;
  DateTime _lastTapAt = DateTime(2000);

  // الترجمة
  SubStyle _subStyle = const SubStyle();
  String _subText = '';
  bool _subOn = true, _stylePanel = false;
  // مسارات منفصلة: الفيديو صورة فقط، والصوت والترجمة ملفات مستقلة (توفير للمساحة)
  late final List<FilmTrack> _audios = _film.audioTracks;
  late final List<FilmTrack> _subTracks = _film.subtitleTracks;
  int _audioIdx = -1; // -1 = صوت الملف نفسه (إن وُجد)
  int _subIdx = -1; // -1 = بدون ترجمة

  // العرض
  BoxFit _fit = BoxFit.contain;
  double _rate = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AdsManager.instance.hideBanner();
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();

    _listen();
    _start();
    FilmPlayerPrefs.loadSkip().then((v) => mounted ? setState(() => _skip = v) : null);
    SubStyle.load().then((v) => mounted ? setState(() => _subStyle = v) : null);
    _scheduleHide();
  }

  Future<void> _start() async {
    if (!_url.startsWith('https://')) {
      setState(() => _error = 'رابط الفيلم غير صالح');
      return;
    }
    final saved = await FilmPlayerPrefs.loadPos(_id);
    try {
      await _player.open(Media(_url, start: saved > 5 ? Duration(seconds: saved) : null));
      // الصوت: آخر لغة اخترتها، وإلا لغة الواجهة، وإلا أول مسار
      final aLang = await FilmPlayerPrefs.loadLang('film_audio_lang');
      var ai = _audios.indexWhere((t) => t.lang == aLang);
      if (ai < 0) ai = _audios.indexWhere((t) => t.lang == L10n.resolved);
      if (ai < 0 && _audios.isNotEmpty) ai = 0;
      if (ai >= 0) await _setAudio(ai, remember: false);
      // الترجمة: آخر اختيار فقط ('off' = بدون)، وأول مرة بدون ترجمة
      final sLang = await FilmPlayerPrefs.loadLang('film_sub_lang');
      final si = sLang.isEmpty || sLang == 'off' ? -1 : _subTracks.indexWhere((t) => t.lang == sLang);
      if (si >= 0) await _setSub(si, remember: false);
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذّر تحميل الفيلم — تأكد من الاتصال بالإنترنت أو أن الرابط ما زال يعمل');
    }
  }

  void _listen() {
    final s = _player.stream;
    _subs.addAll([
      s.position.listen((v) {
        if (!mounted) return;
        if (!_dragging) setState(() => _pos = v);
      }),
      s.duration.listen((v) {
        if (mounted) setState(() {
          _dur = v;
          if (v > Duration.zero) _ready = true;
        });
      }),
      s.buffer.listen((v) => mounted ? setState(() => _buf = v) : null),
      s.playing.listen((v) {
        if (!mounted) return;
        setState(() => _playing = v);
        v ? WakelockPlus.enable() : WakelockPlus.disable();
      }),
      s.buffering.listen((v) => mounted ? setState(() => _buffering = v) : null),
      s.completed.listen((v) {
        if (!mounted || !v) return;
        setState(() {
          _ended = true;
          _controls = true;
        });
        FilmPlayerPrefs.savePos(_id, 0); // انتهى: لا استئناف
      }),
      s.error.listen((e) {
        if (!mounted || e.isEmpty) return;
        setState(() => _error = 'تعذّر تشغيل الفيلم — قد يكون الرابط معطّلاً أو الصيغة غير مدعومة');
      }),
      s.subtitle.listen((lines) {
        if (!mounted) return;
        final t = lines.where((l) => l.trim().isNotEmpty).join('\n');
        if (t != _subText) setState(() => _subText = t);
      }),
    ]);
    // حفظ موضع الاستئناف كل 5 ثوانٍ
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _savePos());
  }

  void _savePos() {
    if (!_ready || _ended) return;
    FilmPlayerPrefs.savePos(_id, _player.state.position.inSeconds);
  }

  // ───── العناصر المساعدة ─────
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing && !_dragging && !_stylePanel) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _togglePlay() {
    if (_ended) {
      _player.seek(Duration.zero);
      setState(() => _ended = false);
    }
    _player.playOrPause();
    _scheduleHide();
  }

  Duration _clamp(Duration d) {
    if (d < Duration.zero) return Duration.zero;
    if (_dur > Duration.zero && d > _dur) return _dur;
    return d;
  }

  void _skipBy(bool forward) {
    final target = _clamp(_player.state.position + Duration(seconds: forward ? _skip : -_skip));
    _player.seek(target);
    setState(() {
      _pos = target;
      _fbForward = forward;
      _fbVisible = true;
    });
    _fbTimer?.cancel();
    _fbTimer = Timer(const Duration(milliseconds: 600), () => mounted ? setState(() => _fbVisible = false) : null);
  }

  /// نقرة واحدة تُظهر/تُخفي الأزرار، ونقرتان متتاليتان على أحد النصفين تقدّمان/ترجعان.
  void _onTap(TapDownDetails d, double width) {
    final now = DateTime.now();
    final side = d.localPosition.dx > width / 2 ? 1 : -1;
    final isDouble = now.difference(_lastTapAt) < const Duration(milliseconds: 280) && _tapSide == side;
    _lastTapAt = now;
    _tapSide = side;
    _lastTap = d.localPosition;
    if (isDouble) {
      _skipBy(side == 1);
      _lastTapAt = DateTime(2000);
    } else {
      Timer(const Duration(milliseconds: 290), () {
        if (mounted && _lastTap == d.localPosition && now == _lastTapAt) _toggleControls();
      });
    }
  }

  Future<void> _pickSkip() async {
    final v = await showSeekPicker(context, _skip);
    if (v != null) {
      setState(() => _skip = v);
      FilmPlayerPrefs.saveSkip(v);
    }
  }

  Future<void> _pickSheet<T>(String title, List<MapEntry<String, T>> items, T current, ValueChanged<T> onPick) async {
    _hideTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xEE14091F),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(title,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              for (final e in items)
                ListTile(
                  title: Text(e.key, style: const TextStyle(color: Colors.white)),
                  trailing: e.value == current ? const Icon(Icons.check_rounded, color: Color(0xFFE040FB)) : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    onPick(e.value);
                  },
                ),
            ],
          ),
        ),
      ),
    );
    _scheduleHide();
  }

  String _trackName(FilmTrack t, int i, String fallback) {
    if (t.title.isNotEmpty) return t.title;
    if (t.lang.isNotEmpty) return L10n.options[t.lang] ?? t.lang;
    return '$fallback ${i + 1}';
  }

  Future<void> _setAudio(int i, {bool remember = true}) async {
    if (i < 0 || i >= _audios.length) return;
    final t = _audios[i];
    try {
      await _player.setAudioTrack(AudioTrack.uri(t.url, title: _trackName(t, i, 'صوت'), language: t.lang));
    } catch (_) {}
    if (mounted) setState(() => _audioIdx = i);
    if (remember) FilmPlayerPrefs.saveLang('film_audio_lang', t.lang);
  }

  Future<void> _setSub(int i, {bool remember = true}) async {
    if (i < 0) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      if (mounted) setState(() {
        _subIdx = -1;
        _subOn = false;
        _subText = '';
      });
      if (remember) FilmPlayerPrefs.saveLang('film_sub_lang', 'off');
      return;
    }
    if (i >= _subTracks.length) return;
    final t = _subTracks[i];
    try {
      await _player.setSubtitleTrack(SubtitleTrack.uri(t.url, title: _trackName(t, i, 'ترجمة'), language: t.lang));
    } catch (_) {}
    if (mounted) setState(() {
      _subIdx = i;
      _subOn = true;
    });
    if (remember) FilmPlayerPrefs.saveLang('film_sub_lang', t.lang);
  }

  void _subtitleMenu() {
    final items = <MapEntry<String, int>>[
      MapEntry('بدون ترجمة', -1),
      for (var i = 0; i < _subTracks.length; i++) MapEntry(_trackName(_subTracks[i], i, 'ترجمة'), i),
    ];
    _pickSheet<int>('الترجمة', items, _subIdx, (i) => _setSub(i));
  }

  void _audioMenu() {
    if (_audios.length < 2) return;
    final items = [for (var i = 0; i < _audios.length; i++) MapEntry(_trackName(_audios[i], i, 'صوت'), i)];
    _pickSheet<int>('الصوت', items, _audioIdx, (i) => _setAudio(i));
  }

  void _speedMenu() {
    const rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    _pickSheet<double>('سرعة التشغيل', [for (final r in rates) MapEntry('${r}x', r)], _rate, (r) {
      _player.setRate(r);
      setState(() => _rate = r);
    });
  }

  Future<void> _exit() async {
    _savePos();
    Navigator.of(context).maybePop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _savePos();
      _player.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _savePos();
    for (final s in _subs) {
      s.cancel();
    }
    _fbTimer?.cancel();
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    WakelockPlus.disable();
    // إيقاف المشغّل أولاً ثم التخلص منه (يقابل _exit_tree في جودوت)
    _player.stop();
    _player.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    super.dispose();
  }

  // ───── الواجهة ─────
  @override
  Widget build(BuildContext context) {
    final title = (FilmState.currentFilm['main_scene'] is Map
            ? (FilmState.currentFilm['main_scene']['title_ar'] ?? '')
            : '')
        .toString();
    final ratio = _dragging
        ? _dragRatio
        : (_dur.inMilliseconds <= 0 ? 0.0 : _pos.inMilliseconds / _dur.inMilliseconds);
    final bufRatio = _dur.inMilliseconds <= 0 ? 0.0 : _buf.inMilliseconds / _dur.inMilliseconds;
    final shownPos = _dragging ? Duration(milliseconds: (_dur.inMilliseconds * _dragRatio).round()) : _pos;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _savePos();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: LayoutBuilder(builder: (context, box) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Video(
                  controller: _video,
                  controls: NoVideoControls,
                  fit: _fit,
                  fill: Colors.black,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
                ),
                // طبقة اللمس
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (d) => _onTap(d, box.maxWidth),
                  child: const SizedBox.expand(),
                ),
                if (_subOn && _subText.isNotEmpty)
                  Positioned(
                    left: 40,
                    right: 40,
                    bottom: _controls ? 100 : 28,
                    child: Center(child: SubtitleOverlay(text: _subText, style: _subStyle)),
                  ),
                Positioned.fill(
                  child: SeekFeedback(visible: _fbVisible, forward: _fbForward, seconds: _skip),
                ),
                if ((_buffering || !_ready) && _error == null)
                  const Center(child: CircularProgressIndicator(color: Color(0xFFE040FB))),
                if (_error != null) _errorView(),
                if (_controls && _error == null) ..._controlsLayer(title, ratio, bufRatio, shownPos),
                if (_stylePanel)
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 340,
                      child: SubtitleStylePanel(
                        style: _subStyle,
                        onChanged: (s) => setState(() => _subStyle = s),
                        onClose: () {
                          _subStyle.save();
                          setState(() => _stylePanel = false);
                          _scheduleHide();
                        },
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 56),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 60),
            child: Text(_error!,
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18)),
          ),
          const SizedBox(height: 16),
          Row(mainAxisSize: MainAxisSize.min, children: [
            FilledButton(
              onPressed: () {
                setState(() {
                  _error = null;
                  _buffering = true;
                });
                _start();
              },
              child: const Text('إعادة المحاولة'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(onPressed: _exit, child: const Text('رجوع')),
          ]),
        ]),
      );

  List<Widget> _controlsLayer(String title, double ratio, double bufRatio, Duration shownPos) {
    Widget icon(IconData i, VoidCallback f, {String? tip}) => IconButton(
          onPressed: () {
            f();
            _scheduleHide();
          },
          tooltip: tip,
          icon: Icon(i, color: Colors.white, size: 28),
        );

    return [
      // شريط علوي
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 24),
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])),
          child: Row(children: [
            IconButton(onPressed: _exit, icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 28)),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            icon(Icons.speed_rounded, _speedMenu, tip: 'السرعة'),
            if (_audios.length > 1)
              icon(Icons.audiotrack_rounded, _audioMenu, tip: 'الصوت'),
            if (_subTracks.isNotEmpty) icon(Icons.closed_caption_rounded, _subtitleMenu, tip: 'الترجمة'),
            if (_subTracks.isNotEmpty)
              icon(Icons.text_fields_rounded, () => setState(() => _stylePanel = true), tip: 'مظهر الترجمة'),
            icon(Icons.timer_rounded, _pickSkip, tip: 'مدة التقديم'),
            icon(_fit == BoxFit.contain ? Icons.fit_screen_rounded : Icons.crop_free_rounded, () {
              setState(() => _fit = _fit == BoxFit.contain ? BoxFit.cover : BoxFit.contain);
            }, tip: 'ملء الشاشة'),
          ]),
        ),
      ),
      // الأزرار الوسطى
      Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              iconSize: 44,
              onPressed: () => _skipBy(false),
              icon: const Icon(Icons.replay_10_rounded, color: Colors.white)),
          const SizedBox(width: 28),
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              child: Icon(
                  _ended ? Icons.replay_rounded : (_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  color: const Color(0xFFE040FB),
                  size: 56),
            ),
          ),
          const SizedBox(width: 28),
          IconButton(
              iconSize: 44,
              onPressed: () => _skipBy(true),
              icon: const Icon(Icons.forward_10_rounded, color: Colors.white)),
        ]),
      ),
      // الشريط السفلي
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])),
          child: Row(children: [
            Text(fmtTime(shownPos), style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(width: 14),
            Expanded(
              // الشريط يعمل باتجاه يسار→يمين دائماً مهما كان اتجاه الواجهة
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: SafeSeekBar(
                  ratio: ratio,
                  buffered: bufRatio,
                  enabled: _ready,
                  onStart: () {
                    _hideTimer?.cancel();
                    setState(() {
                      _dragging = true;
                      _dragRatio = ratio;
                    });
                  },
                  onUpdate: (r) => setState(() => _dragRatio = r),
                  onEnd: (r) {
                    final t = Duration(milliseconds: (_dur.inMilliseconds * r).round());
                    _player.seek(t);
                    setState(() {
                      _dragging = false;
                      _pos = t;
                      _ended = false;
                    });
                    _scheduleHide();
                  },
                ),
              ),
            ),
            const SizedBox(width: 14),
            Text(fmtTime(_dur), style: const TextStyle(color: Colors.white, fontSize: 16)),
          ]),
        ),
      ),
    ];
  }
}
