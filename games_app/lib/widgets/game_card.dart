import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/colors.dart';
import 'glow_button.dart';
import 'net_loader.dart';
import 'rating_bar.dart';
import 'title_marquee.dart';
import 'ui_image.dart';

Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// يقابل MovieTemplate.tscn — بطاقة لعبة 317x520 (+ هامش 20) بإطار وظل بنفسجي.
/// بوستر 300x400، عنوان متحرك، شريط تقييم IMDB بالنجوم، وأيقونة التقييم.
class GameCard extends StatefulWidget {
  final Map<String, dynamic> game;
  final Uint8List? posterBytes; // إن وُجدت (صف "تابع اللعب")
  final void Function(Map<String, dynamic> game, Uint8List? posterBytes) onTap;
  final ValueChanged<Uint8List>? onPosterLoaded;

  const GameCard({
    super.key,
    required this.game,
    required this.onTap,
    this.posterBytes,
    this.onPosterLoaded,
  });

  @override
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard> {
  Uint8List? _poster;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _poster = widget.posterBytes;
    _loaded = _poster != null;
  }

  @override
  Widget build(BuildContext context) {
    final main = _m(widget.game['main_scene']);
    final title = (main['title_ar'] ?? '').toString();
    final posterUrl = (main['poster_url'] ?? '').toString();
    final imdb = double.tryParse((main['imdb_rating'] ?? 0).toString()) ?? 0;
    final iconType = int.tryParse((main['rating_icon_type'] ?? 0).toString()) ?? 0;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 317,
        height: 520,
        child: Stack(
          children: [
            // الإطار (خلفية البطاقة)
            Positioned.fill(
              child: Image.asset('assets/images/m1n_a1a.webp', fit: BoxFit.fill),
            ),
            // الوميض الخارجي (ظل بنفسجي)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(34),
                    bottomRight: Radius.circular(34),
                    bottomLeft: Radius.circular(34),
                  ),
                  boxShadow: [BoxShadow(color: AppColors.cardShadow.withOpacity(0.7), blurRadius: 30)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                children: [
                  // البوستر
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(25),
                      bottomRight: Radius.circular(15),
                      bottomLeft: Radius.circular(15),
                    ),
                    child: SizedBox(
                      width: 299,
                      height: 400,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_poster != null)
                            AnimatedOpacity(
                              opacity: _loaded ? 1 : 0,
                              duration: const Duration(milliseconds: 400),
                              child: Image.memory(_poster!, fit: BoxFit.cover, gaplessPlayback: true),
                            )
                          else
                            NetImage(
                              url: posterUrl,
                              fit: BoxFit.cover,
                              fade: const Duration(milliseconds: 400),
                              onLoaded: (b) {
                                widget.onPosterLoaded?.call(b);
                                if (mounted) {
                                  setState(() {
                                    _poster = b;
                                    _loaded = true;
                                  });
                                }
                              },
                            ),
                          // مؤشر تحميل البطاقة
                          Center(child: NetLoader(width: 160, height: 160, loading: _poster == null)),
                          // زر النقر + توهج
                          Positioned.fill(
                            child: GlowButton(
                              onTap: () {
                                if (AppState.inputBlocked) return;
                                widget.onTap(widget.game, _poster);
                              },
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // العنوان
                  SizedBox(
                    height: 53,
                    child: Center(child: TitleMarquee(text: title, width: 290, height: 53, fontSize: 30)),
                  ),
                  // صف التقييم
                  SizedBox(
                    height: 35,
                    child: Row(
                      children: [
                        _ratingIcon(iconType),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: RatingBar(
                            value: imdb,
                            max: 10,
                            width: 160,
                            height: 35,
                            tapeAsset: 'assets/images/m1n_a1c.jpg',
                            maskAsset: 'assets/images/m1n_a1e.webp',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ratingIcon(int type) {
    // 1 = شعار التطبيق، 2 = أيقونة التحذير، غير ذلك = مخفية
    String? asset;
    if (type == 1) asset = 'assets/images/a1a.webp';
    if (type == 2) asset = 'assets/images/a1o.png';
    if (asset == null) return const SizedBox(width: 60, height: 35);
    return SizedBox(width: 60, height: 35, child: Image.asset(asset, fit: BoxFit.contain));
  }
}
