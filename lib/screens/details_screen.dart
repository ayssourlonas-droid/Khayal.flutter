import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/app_state.dart';
import '../core/colors.dart';
import '../core/data_repository.dart';
import '../core/game_library.dart';
import '../core/player_points.dart';
import '../widgets/design.dart';
import '../widgets/divided_images.dart';
import '../widgets/glow_button.dart';
import '../widgets/nav.dart';
import '../widgets/rating_bar.dart';
import '../widgets/ui_image.dart';
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

  late final Ticker _ticker;
  final ValueNotifier<double> _t = ValueNotifier(0);

  // الصفحات: 0 معرض، 1 وصف، 2 طاقم — (يقابل Extra / Desc / Cast)
  late final List<bool> _active;
  int _selected = 1;
  Uint8List? _bgBytes;
  Uint8List? _posterBytes;

  late final List<Map<String, dynamic>> _special;
  late final List<Map<String, dynamic>> _cast;
  late final String _description;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _t.value = d.inMicroseconds / 1e6)..start();

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

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  // ───── التشغيل ─────
  void _play() {
    // لا نخصم نقطة إن كانت اللعبة غير صالحة
    if (GameLibrary.validate(game).isNotEmpty) return;
    if (PlayerPoints.instance.usePoint()) {
      Nav.push(const GameScreen());
    } else {
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

          // البوستر + ظله الكبير
          Positioned(
            left: 50,
            top: 200,
            width: 500,
            height: 700,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  bottom: 0,
                  width: 400,
                  height: 600,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.706), blurRadius: 100)],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: _posterBytes != null
                      ? Image.memory(_posterBytes!, fit: BoxFit.cover, gaplessPlayback: true)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),

          // العنوان + الوسوم + السنة
          Positioned(
            right: 0,
            top: 230,
            width: 500,
            child: Column(
              children: [
                SizedBox(
                  height: 70,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: OutlinedText(title,
                        size: 45, color: AppColors.titleRed, outlineColor: const Color.fromRGBO(15, 0, 15, 0.92), outline: 15),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [BoxShadow(color: const Color.fromRGBO(51, 6, 46, 0.745), blurRadius: 20)],
                  ),
                  child: SizedBox(
                    width: 500,
                    child: Column(
                      children: [
                        Container(
                          height: 100,
                          alignment: Alignment.center,
                          color: const Color.fromRGBO(0, 0, 0, 0.988),
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
                SizedBox(
                  height: 100,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedText(year,
                            size: 45, color: AppColors.titleRed, outlineColor: const Color.fromRGBO(15, 0, 15, 0.92), outline: 15),
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
                  _ratingRow(imdb, 'assets/images/m2_a1c.jpg', const Color.fromRGBO(251, 0, 255, 0.392), 'IMDB'),
                  const SizedBox(height: 10),
                  _ratingRow(app != null ? app * 10 : 90, 'assets/images/m2_a1m.jpg',
                      const Color.fromRGBO(178, 0, 173, 0.392), 'خيال'),
                  const SizedBox(height: 10),
                  _ratingRow(90, 'assets/images/m2_a1n.jpg', const Color.fromRGBO(242, 0, 255, 0.392), 'الجمهور'),
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

          // مناطق التنقل (شفافة كما في الأصل): طاقم / وصف / معرض
          Positioned(
            top: h - 690,
            left: (1080 - 470) / 2,
            width: 470,
            height: 100,
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                for (final entry in const [(0, 'extra'), (1, 'desc'), (2, 'cast')]) ...[
                  if (_active[entry.$1])
                    GlowButton(
                      onTap: () => setState(() => _selected = entry.$1),
                      child: const SizedBox(width: 150, height: 100),
                    )
                  else
                    const SizedBox(width: 150, height: 100),
                  const SizedBox(width: 10),
                ],
              ],
            ),
          ),

          // رجوع (أعلى اليمين) و تشغيل
          Positioned(
            right: 25,
            top: 25,
            child: GlowButton(
              onTap: () => Navigator.of(context).maybePop(),
              child: SizedBox(width: 200, height: 100, child: Image.asset('assets/images/a1c.webp', fit: BoxFit.contain)),
            ),
          ),
          Positioned(
            right: 25,
            top: h / 2 - 10,
            child: GlowButton(
              onTap: _play,
              child: SizedBox(width: 200, height: 100, child: Image.asset('assets/images/a1d.webp', fit: BoxFit.contain)),
            ),
          ),
        ],
      ),
    );
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
            maskAsset: 'assets/images/m2_a1e.png',
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
