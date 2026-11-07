import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'ads_manager.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'colors.dart';
import 'data_repository.dart';
import 'game_library.dart';
import 'player_points.dart';
import 'alert_popup.dart';
import 'design.dart';
import 'divided_images.dart';
import 'glow_button.dart';
import 'sound_fx.dart';
import 'nav.dart';
import 'rating_bar.dart';
import 'ui_image.dart';
import 'game_screen.dart';
import 'settings_screen.dart';

Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List _l(dynamic v) => v is List ? v : const [];

/// يقابل DetailsScreen.gd/.tscn — صفحة تفاصيل اللعبة.
class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> with SingleTickerProviderStateMixin {
  late final Map<String, dynamic> game = AppState.currentGame;
  late final Map<String, dynamic> main = _m(game['main_scene']);
  late final Map<String, dynamic> details = _m(game['details_scene']);

  // أبعاد الكرت (غيّرها هنا إن أردت تجربة حجم آخر)
  static const double _posterLeft = 50;
  static const double _posterTop = 200;
  static const double _posterW = 450;
  static const double _posterH = 700;

  late final Ticker _ticker;
  final ValueNotifier<double> _t = ValueNotifier(0);

  // الصفحات: 0 معرض، 1 وصف، 2 طاقم — (يقابل Extra / Desc / Cast)
  late final List<bool> _active;
  int _selected = 1;
  bool _toolsOpen = false;
  Uint8List? _bgBytes;
  Uint8List? _posterBytes;

  // إعجاب / مفضلة / تقييمي الشخصي: تُحفظ على هذا الجهاز فقط (لا خادم بعد)
  bool _liked = false;
  bool _fav = false;
  int _myRate = 0;
  String get _gid => (game['id'] ?? game['title'] ?? '').toString();

  late final List<Map<String, dynamic>> _special;
  late final List<Map<String, dynamic>> _cast;
  late final String _description;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _t.value = d.inMicroseconds / 1e6)..start();

    _loadFlags();
    _posterBytes = AppState.currentPoster;
    _bgBytes = AppState.currentBackground;
    final posterUrl = (main['poster_url'] ?? '').toString();
    if (_posterBytes == null) {
      ImageStore.get(posterUrl).then((b) {
        if (mounted && b != null) setState(() => _posterBytes = b);
      });
    }
    if (_bgBytes == null) {
      ImageStore.get((details['background_url'] ?? '').toString()).then((b) {
        if (mounted && b != null) setState(() => _bgBytes = b);
      });
    }

    _description = '${details['description'] ?? ''}\n\n${GameLibrary.creditLine(game)}';
    _cast = _l(details['cast']).map(_m).toList();

    var special = _l(details['special_items']).map(_m).toList();
    if (special.isEmpty) {
      final u1 = (details['extra_image_1'] ?? '').toString().trim();
      final u2 = (details['extra_image_2'] ?? '').toString().trim();
      if (u1.startsWith('http') || u2.startsWith('http')) {
        special = [
          {
            'item_name': game['title'] ?? '',
            'main_photo_url': u1,
            'sub_photo_url': u2,
          }
        ];
      }
    }
    _special = special;

    AppState.currentGameUrl = (details['play_url'] ?? '').toString();

    _active = [
      _special.isNotEmpty,
      _description.trim().isNotEmpty,
      _cast.isNotEmpty,
    ];
    if (!_active[1]) _selected = _active.indexOf(true).clamp(0, 2).toInt();
  }

  Future<void> _loadFlags() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _liked = sp.getBool('like_$_gid') ?? false;
        _fav = sp.getBool('fav_$_gid') ?? false;
        _myRate = sp.getInt('rate_$_gid') ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _saveFlag(String key, Object? v) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (v == null || v == false || v == 0) {
        await sp.remove(key);
      } else if (v is bool) {
        await sp.setBool(key, v);
      } else if (v is int) {
        await sp.setInt(key, v);
      }
    } catch (_) {}
  }

  void _toggleLike() {
    SoundFx.instance.play(Sfx.tap);
    setState(() => _liked = !_liked);
    _saveFlag('like_$_gid', _liked);
  }

  void _toggleFav() {
    SoundFx.instance.play(Sfx.tap);
    setState(() => _fav = !_fav);
    _saveFlag('fav_$_gid', _fav);
  }

  Future<void> _rate() async {
    SoundFx.instance.play(Sfx.open);
    final r = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF14091F),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('قيّم هذه اللعبة',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                textDirection: TextDirection.ltr,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      iconSize: 44,
                      onPressed: () => Navigator.pop(c, i),
                      icon: Icon(i <= _myRate ? Icons.star_rounded : Icons.star_border_rounded,
                          color: const Color(0xFFFFC83D)),
                    ),
                ],
              ),
              if (_myRate > 0)
                TextButton(
                    onPressed: () => Navigator.pop(c, 0),
                    child: const Text('إزالة تقييمي', style: TextStyle(color: Colors.white54))),
            ],
          ),
        ),
      ),
    );
    if (r == null || !mounted) return;
    setState(() => _myRate = r);
    _saveFlag('rate_$_gid', r);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  // ───── التشغيل ─────
  void _play() {
    // لا نخصم نقطة إن كانت اللعبة غير صالحة
    if (GameLibrary.validate(game).isNotEmpty) {
      SoundFx.instance.play(Sfx.error);
      return;
    }
    if (PlayerPoints.instance.usePoint()) {
      SoundFx.instance.play(Sfx.confirm);
      AdsManager.instance.showInterstitialThen(() => Nav.push(const GameScreen()));
    } else {
      SoundFx.instance.play(Sfx.error);
      Nav.push(const SettingsScreen()); // لا نقاط → الإعدادات
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GodotGradientBox(
        loadingGradient,
        child: Design(builder: (context, h) => _body(h)),
      ),
    );
  }

  Widget _body(double h) {
    final title = (main['title_ar'] ?? '').toString();
    final tags = _l(game['category_tags']).map((e) => e.toString()).toList();
    final primary = tags.isNotEmpty ? tags.first : (details['category'] ?? '').toString();
    final secondary = tags.length > 1 ? tags.skip(1).join(' • ') : '';
    final year = (game['release_year'] ?? '').toString();
    final imdb = (double.tryParse((main['imdb_rating'] ?? 0).toString()) ?? 0) * 10;
    final app = double.tryParse((main['app_rating'] ?? '').toString());

    return ClipRect(
      child: Stack(
        children: [
          // الخلفية المتحركة (top_page_movement: إزاحة دائرية 1% بسرعة 0.5)
          Positioned(
            left: (1080 - 1920) / 2,
            top: (h - 2000) / 2,
            width: 1920,
            height: 2000,
            child: AnimatedBuilder(
              animation: _t,
              builder: (_, child) => Transform.translate(
                offset: Offset(math.sin(_t.value * 0.5) * 0.01 * 1920, math.cos(_t.value * 0.5) * 0.01 * 2000),
                child: child,
              ),
              child: _bgBytes != null
                  ? Image.memory(_bgBytes!, fit: BoxFit.cover, gaplessPlayback: true)
                  : const SizedBox.shrink(),
            ),
          ),

          // البوستر كـ«كرت عائم»: ظل أسود ضبابي يظهر تحته ومن جانبه الأيسر
          Positioned(
            left: _posterLeft,
            top: _posterTop,
            width: _posterW,
            height: _posterH,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.9),
                    blurRadius: 90,
                    spreadRadius: 4,
                    offset: const Offset(-14, 34),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _posterBytes != null
                    ? Image.memory(_posterBytes!,
                        width: _posterW, height: _posterH, fit: BoxFit.cover, gaplessPlayback: true)
                    : const ColoredBox(color: Color(0xFF14091F)),
              ),
            ),
          ),

          // شريط ظاهر دائماً تحت الكرت: إعجاب / تقييم / مفضلة
          Positioned(
            left: _posterLeft,
            top: _posterTop + _posterH + 40,
            width: _posterW,
            child: _actionBar(),
          ),

          // العنوان + الوسوم + السنة
          Positioned(
            right: 0,
            top: 230,
            width: 500,
            child: Column(
              children: [
                SizedBox(
                  height: 80,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: OutlinedText(title,
                        size: 45, color: AppColors.titleRed, outlineColor: const Color.fromRGBO(15, 0, 15, 1), outline: 20),
                  ),
                ),
                const SizedBox(height: 14),
                DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [BoxShadow(color: const Color.fromRGBO(51, 6, 46, 0.745), blurRadius: 20)],
                  ),
                  child: SizedBox(
                    width: 500,
                    child: Column(
                      children: [
                        Container(
                          height: 90,
                          alignment: Alignment.center,
                          child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: OutlinedText(primary, size: 45, outline: 10, outlineColor: AppColors.purpleOutline)),
                        ),
                        SizedBox(
                          height: 50,
                          child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: OutlinedText(secondary, size: 35, outline: 10, outlineColor: AppColors.purpleOutline)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 100,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedText(year,
                            size: 45, outline: 10, outlineColor: AppColors.purpleOutline),
                      ),
                      SizedBox(
                        width: 300,
                        child: OutlinedText('سنة الصدور :',
                            size: 45, color: AppColors.titleRed, outlineColor: const Color.fromRGBO(15, 0, 15, 0.92), outline: 15),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // التقييمات
          Positioned(
            right: 15,
            top: 650,
            width: 485,
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [BoxShadow(color: const Color.fromRGBO(74, 2, 60, 0.745), blurRadius: 20)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ratingRow(imdb, 'assets/images/a1q.webp', const Color.fromRGBO(251, 0, 255, 0.392), 'IMDB'),
                  const SizedBox(height: 10),
                  _ratingRow(app != null ? app * 10 : 90, 'assets/images/a1r.webp',
                      const Color.fromRGBO(178, 0, 173, 0.392), 'خيال'),
                  const SizedBox(height: 10),
                  _ratingRow(90, 'assets/images/a1s.webp', const Color.fromRGBO(242, 0, 255, 0.392), 'الجمهور'),
                ],
              ),
            ),
          ),

          // صفحات الأسفل (معرض / وصف / طاقم) بالانزلاق
          Positioned(
            left: 0,
            right: 0,
            top: h - 690,
            height: 550,
            child: _carousel(),
          ),

          // شريط التبديل الظاهر دائماً: معرض / وصف / طاقم
          Positioned(
            top: h - 800,
            left: 0,
            right: 0,
            height: 100,
            child: Center(child: _tabsBar()),
          ),

          // رجوع (أعلى اليمين) و تشغيل
          Positioned(
            right: 25,
            top: 25,
            child: GlowButton(
              sound: Sfx.back,
              onTap: () => Navigator.of(context).maybePop(),
              child: SizedBox(width: 200, height: 100, child: Image.asset('assets/images/a1c.webp', fit: BoxFit.contain)),
            ),
          ),
          _toolsBar(),
          Positioned(
            right: 25,
            top: h / 2 - 10,
            child: GlowButton(
              sound: null, // _play يختار التأكيد أو الخطأ
              onTap: _play,
              child: SizedBox(width: 200, height: 100, child: Image.asset('assets/images/a1d.webp', fit: BoxFit.contain)),
            ),
          ),
        ],
      ),
    );
  }


  // ───── الشريط الدائم تحت الكرت ─────
  Widget _actionBar() {
    Widget btn(IconData icon, String label, bool on, Color onColor, VoidCallback tap) => GlowButton(
          sound: null, // كل زر يشغّل صوته
          onTap: tap,
          child: SizedBox(
            width: 130,
            height: 90,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 46, color: on ? onColor : Colors.white70),
                Text(label,
                    style: TextStyle(
                        fontSize: 22,
                        color: on ? Colors.white : Colors.white60,
                        decoration: TextDecoration.none)),
              ],
            ),
          ),
        );
    return Container(
      height: 110,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.88),
        borderRadius: BorderRadius.circular(55),
        border: Border.all(color: AppColors.popupBorder, width: 4),
        boxShadow: const [BoxShadow(color: Color.fromRGBO(74, 2, 60, 0.745), blurRadius: 20)],
      ),
      child: Row(
        textDirection: TextDirection.ltr,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          btn(_liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, 'إعجاب', _liked,
              const Color(0xFFFF4D8D), _toggleLike),
          btn(_myRate > 0 ? Icons.star_rounded : Icons.star_border_rounded,
              _myRate > 0 ? 'تقييمي $_myRate' : 'تقييم', _myRate > 0, const Color(0xFFFFC83D), _rate),
          btn(_fav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, 'مفضلة', _fav,
              const Color(0xFF7CC4FF), _toggleFav),
        ],
      ),
    );
  }

  // ───── شريط التبديل السفلي ─────
  static const _tabs = [
    (0, Icons.photo_library_rounded, 'معرض'),
    (1, Icons.notes_rounded, 'وصف'),
    (2, Icons.groups_rounded, 'طاقم'),
  ];

  Widget _tabsBar() {
    final visible = [for (final t in _tabs) if (_active[t.$1]) t];
    if (visible.isEmpty) return const SizedBox.shrink();
    final sel = _active[_selected] ? _selected : visible.first.$1;
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.88),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: AppColors.popupBorder, width: 4),
        boxShadow: const [BoxShadow(color: Color.fromRGBO(74, 2, 60, 0.745), blurRadius: 20)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.ltr,
        children: [
          for (final t in visible)
            GlowButton(
              onTap: () => setState(() => _selected = t.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 150,
                height: 80,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: sel == t.$1 ? AppColors.popupBorder.withOpacity(0.35) : Colors.transparent,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(t.$2, size: 40, color: sel == t.$1 ? Colors.white : Colors.white60),
                    Text(
                      t.$3,
                      style: TextStyle(
                        fontSize: 24,
                        color: sel == t.$1 ? Colors.white : Colors.white60,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ───── شريط الأدوات (ينزلق من الزر أعلى اليسار) ─────
  static const _reasons = [
    'اللعبة لا تفتح',
    'شاشة سوداء أو فارغة',
    'تعليق أو بطء شديد',
    'اللمس أو الأزرار لا تعمل',
    'محتوى غير مناسب',
    'مخالفة حقوق / رخصة',
    'مشكلة أخرى',
  ];

  List<(IconData, String, VoidCallback)> get _tools => [
        (Icons.flag_rounded, 'إبلاغ', _report),
        (Icons.ios_share_rounded, 'مشاركة', _shareApp),
      ];

  Widget _toolsBar() {
    final tools = _tools;
    const btn = 110.0;
    return Positioned(
      left: 25,
      top: 25,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        width: _toolsOpen ? 100.0 + tools.length * btn : 100.0,
        height: 100,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(_toolsOpen ? 0.88 : 0.0),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: _toolsOpen ? AppColors.popupBorder : Colors.transparent, width: 4),
        ),
        child: Row(
          textDirection: TextDirection.ltr,
          children: [
            GlowButton(
              sound: null, // صوت الفتح/الإغلاق يُشغَّل أدناه
              onTap: () {
                SoundFx.instance.play(_toolsOpen ? Sfx.close : Sfx.open);
                setState(() => _toolsOpen = !_toolsOpen);
              },
              child: SizedBox(
                width: 100,
                height: 100,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  // مغلق: a2a (أربعة مربعات) — مفتوح: a1z (المعيّن المائل)، بتلاشي متبادل
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedOpacity(
                        opacity: _toolsOpen ? 0 : 1,
                        duration: const Duration(milliseconds: 250),
                        child: Image.asset(
                          'assets/images/a2a.webp',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.apps_rounded, size: 64, color: Colors.white),
                        ),
                      ),
                      AnimatedOpacity(
                        opacity: _toolsOpen ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: Image.asset(
                          'assets/images/a1z.webp',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.apps_rounded, size: 64, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: IgnorePointer(
                ignoring: !_toolsOpen,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: tools.length * btn,
                    child: AnimatedOpacity(
                      opacity: _toolsOpen ? 1 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: Row(
                        textDirection: TextDirection.ltr,
                        children: [
                          for (final t in tools)
                            GlowButton(
                              onTap: t.$3,
                              child: SizedBox(
                                width: btn,
                                height: 100,
                                child: Icon(t.$1, size: 60, color: Colors.white),
                              ),
                            ),
                        ],
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

  Future<void> _shareApp() async {
    setState(() => _toolsOpen = false);
    if (AppState.appPageUrl.isEmpty) {
      await showAlertPopup(context,
          title: 'غير متاح حالياً',
          message: 'رابط مشاركة التطبيق غير متوفر حالياً، حاول لاحقاً.',
          buttons: const [PopupBtn(' حسناً ', 1)]);
      return;
    }
    await Clipboard.setData(ClipboardData(text: AppState.appPageUrl));
    if (!mounted) return;
    await showAlertPopup(context,
        title: 'تم النسخ ✅',
        message: 'تم نسخ رابط التطبيق. شاركه مع أصدقائك!',
        buttons: const [PopupBtn(' موافق ', 2)]);
  }

  /// إبلاغ عن مشكلة في اللعبة: يختار اللاعب السبب فيُجهَّز نص البلاغ ويُفتح بريد/واتساب الدعم.
  /// (لا خادم لدينا: النص يُنسخ أيضاً إلى الحافظة.)
  Future<void> _report() async {
    setState(() => _toolsOpen = false);
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14091F),
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('ما المشكلة في هذه اللعبة؟',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              for (final r in _reasons)
                ListTile(title: Text(r, style: const TextStyle(color: Colors.white)), onTap: () => Navigator.pop(c, r)),
              ListTile(
                  title: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
                  onTap: () => Navigator.pop(c)),
            ],
          ),
        ),
      ),
    );
    if (reason == null || !mounted) return;

    String version = '';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    final title = (main['title_ar'] ?? '').toString();
    final subject = 'بلاغ عن لعبة: $title';
    final body = 'اللعبة: $title (#${game['id'] ?? ''})\n'
        'المشكلة: $reason\n'
        'الرابط: ${details['play_url'] ?? ''}\n'
        'إصدار التطبيق: $version';
    await Clipboard.setData(ClipboardData(text: '$subject\n$body'));

    String? target;
    if (AppState.supportEmail.isNotEmpty) {
      target = 'mailto:${AppState.supportEmail}?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';
    } else if (AppState.supportWhatsappUrl.isNotEmpty) {
      target = AppState.supportWhatsappUrl;
    }
    if (target != null) {
      try {
        await launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (!mounted) return;
    await showAlertPopup(context,
        title: 'شكراً لك ✅',
        message: target == null
            ? 'وسيلة التواصل غير متوفرة الآن، لكن نُسخ نص البلاغ؛ أرسله لنا لاحقاً.'
            : 'جُهّز البلاغ وفُتح تطبيق الإرسال. إن لم يظهر فقد نُسخ النص إلى الحافظة.',
        buttons: const [PopupBtn(' موافق ', 2)]);
  }

  Widget _ratingRow(double value, String tape, Color tint, String caption) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      textDirection: TextDirection.ltr,
      children: [
        Container(
          width: 300,
          height: 45,
          decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(4)),
          child: RatingBar(
            value: value,
            max: 100,
            width: 300,
            height: 45,
            tapeAsset: tape,
            maskAsset: 'assets/images/a1k.webp',
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 100,
          height: 45,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color.fromRGBO(0, 0, 0, 0.49), Color.fromRGBO(184, 121, 189, 0.49)]),
          ),
          child: Text(caption, style: const TextStyle(fontSize: 28, color: Colors.white, decoration: TextDecoration.none)),
        ),
      ],
    );
  }

  // ───── الكاروسيل السفلي ─────
  Widget _carousel() {
    final visible = [for (var i = 0; i < 3; i++) if (_active[i]) i];
    if (visible.isEmpty) return const SizedBox.shrink();
    var sel = visible.contains(_selected) ? _selected : visible.first;
    final pos = visible.indexOf(sel);

    Widget page(int i) {
      switch (i) {
        case 0:
          return _page('معرض الصور', _gallery());
        case 1:
          return _page('الوصف', _descriptionBox());
        default:
          return _page('الطاقم', _castList());
      }
    }

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        // RTL: سحب لليسار = التالي
        final dir = v > 0 ? 1 : (v < 0 ? -1 : 0);
        final np = (pos + dir).clamp(0, visible.length - 1).toInt();
        setState(() => _selected = visible[np]);
      },
      child: ClipRect(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: pos.toDouble()),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutSine,
          builder: (_, p, __) => Stack(
            children: [
              for (var k = 0; k < visible.length; k++)
                Positioned(
                  left: (p - k) * 1080,
                  top: 0,
                  width: 1080,
                  height: 550,
                  child: page(visible[k]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _page(String title, Widget body) => Column(
        children: [
          SizedBox(
            width: 980,
            height: 70,
            child: Center(
              child: OutlinedText(title,
                  size: 45, color: const Color.fromRGBO(255, 59, 59, 1), outlineColor: const Color.fromRGBO(15, 0, 15, 1), outline: 15),
            ),
          ),
          SizedBox(width: 980, height: 480, child: body),
        ],
      );

  Widget _descriptionBox() => SingleChildScrollView(
        child: Text(
          _description,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 50, color: Colors.white, height: 1.15, decoration: TextDecoration.none),
        ),
      );

  Widget _gallery() => ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _special.length,
        separatorBuilder: (_, __) => const SizedBox(width: 20),
        itemBuilder: (_, i) {
          final it = _special[i];
          final raw = [it['main_photo_url'], it['sub_photo_url'], it['extra_photo_url']]
              .map((e) => (e ?? '').toString().trim())
              .where((u) => u.isNotEmpty && u != '0' && u.startsWith('http'))
              .toList();
          return SizedBox(
            width: 350,
            height: 500,
            child: Column(
              children: [
                DividedImages(urls: raw, width: 350, height: 400),
                SizedBox(
                  height: 100,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: OutlinedText((it['item_name'] ?? 'مجهول').toString(),
                        size: 45, outline: 10, outlineColor: AppColors.purpleOutline),
                  ),
                ),
              ],
            ),
          );
        },
      );

  Widget _castList() => ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _cast.length,
        separatorBuilder: (_, __) => const SizedBox(width: 20),
        itemBuilder: (_, i) {
          final a = _cast[i];
          final url = (a['photo_url'] ?? '').toString().trim();
          return SizedBox(
            width: 150,
            height: 200,
            child: Column(
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: url.startsWith('http') ? NetImage(url: url, width: 150, height: 150) : const SizedBox.shrink(),
                ),
                Expanded(
                  child: Text(
                    (a['original_name'] ?? '').toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, color: Colors.white, decoration: TextDecoration.none),
                  ),
                ),
              ],
            ),
          );
        },
      );
}
