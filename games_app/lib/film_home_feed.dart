import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Text;

import 'l10n.dart';
import 'colors.dart';
import 'favorites.dart';
import 'film_data.dart';
import 'glow_button.dart';
import 'ui_image.dart';

typedef OpenFilm = void Function(Map<String, dynamic> film, Uint8List? poster);

Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
String _id(Map<String, dynamic> f) => (f['id'] ?? '').toString();
String _title(Map<String, dynamic> f) => (_m(f['main_scene'])['title_ar'] ?? '').toString();
String _poster(Map<String, dynamic> f) => (_m(f['main_scene'])['poster_url'] ?? '').toString();
List<String> _tags(Map<String, dynamic> f) =>
    f['category_tags'] is List ? (f['category_tags'] as List).map((e) => e.toString()).toList() : <String>[];

/// بذرة اليوم (بتوقيت الجهاز): تتغير مرة واحدة كل يوم، فتبقى توصيات اليوم ثابتة طوال اليوم.
int _daySeed() {
  final d = DateTime.now();
  return d.year * 10000 + d.month * 100 + d.day;
}

/// الصفحة الرئيسية للأفلام: «تابع المشاهدة» ← «المفضلة» ← «فيلم اليوم» + كلمات مقترحة.
/// نسخة من HomeFeed بنصوص الأفلام، ومفاتيح المفضلة بادئتها «film_».
class FilmHomeFeed extends StatefulWidget {
  final List<Map<String, dynamic>> films;
  final Map<String, dynamic>? fallbackLast; // آخر فيلم في هذه الجلسة إن لم يكن محفوظاً
  final OpenFilm onOpen;
  final ValueChanged<String> onTag;
  const FilmHomeFeed({super.key, required this.films, required this.onOpen, required this.onTag, this.fallbackLast});

  @override
  State<FilmHomeFeed> createState() => _FilmHomeFeedState();
}

class _FilmHomeFeedState extends State<FilmHomeFeed> {
  static const _font = 'Tajawal';
  static const _lav = Color(0xFFE3B8FF);

  String _lastId = '';

  @override
  void initState() {
    super.initState();
    Favorites.instance.ensureLoaded();
    FilmRepository.readLastId().then((id) {
      if (mounted) setState(() => _lastId = id);
    });
  }

  Map<String, dynamic>? _byId(String id) {
    if (id.isEmpty) return null;
    for (final f in widget.films) {
      if (_id(f) == id) return f;
    }
    return null;
  }

  Map<String, dynamic>? get _last => _byId(_lastId) ?? widget.fallbackLast;

  /// المفضلة: معرّفاتها محفوظة بالبادئة «film_» (تُهمل معرّفات الألعاب).
  List<Map<String, dynamic>> get _favs {
    final out = <Map<String, dynamic>>[];
    for (final key in Favorites.instance.ids) {
      if (!key.startsWith('film_')) continue;
      final f = _byId(key.substring(5));
      if (f != null) out.add(f);
    }
    return out;
  }

  /// فيلم اليوم: اختيار ثابت ليوم كامل من أفلام غير آخر فيلم.
  Map<String, dynamic>? _today(String exceptId) {
    final pool = widget.films.where((f) => _id(f) != exceptId && _id(f).isNotEmpty).toList()
      ..sort((a, b) => _id(a).compareTo(_id(b))); // ترتيب ثابت كي لا يتغير الاختيار بتغير ترتيب القائمة
    if (pool.isEmpty) return null;
    return pool[Random(_daySeed()).nextInt(pool.length)];
  }

  /// كلمات مقترحة (وسوم): أولاً وسوم تشبه ما يحبه المشاهد (آخر فيلم والمفضلة) ثم وسوم أخرى، بترتيب يتبدّل يومياً.
  List<String> _suggestedTags(Map<String, dynamic>? last, List<Map<String, dynamic>> favs) {
    final taste = <String>{};
    if (last != null) taste.addAll(_tags(last));
    for (final f in favs) {
      taste.addAll(_tags(f));
    }
    final all = <String>{};
    for (final f in widget.films) {
      all.addAll(_tags(f));
    }
    final rnd = Random(_daySeed());
    List<String> shuffled(Iterable<String> s) => (s.toList()..sort())..shuffle(rnd);
    final out = <String>[
      ...shuffled(taste.where(all.contains)).take(4),
      ...shuffled(all.where((t) => !taste.contains(t))).take(4),
    ];
    return out.take(6).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: _font, decoration: TextDecoration.none),
        child: ListenableBuilder(
          listenable: Favorites.instance,
          builder: (_, __) {
            final last = _last;
            final favs = _favs;
            final today = _today(last == null ? '' : _id(last));
            final tags = _suggestedTags(last, favs);
            return Padding(
              padding: const EdgeInsets.fromLTRB(40, 10, 40, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (last != null) ...[
                    _label('تابع المشاهدة', Icons.play_circle_fill),
                    _BigCard(film: last, button: 'تابع ▶', accent: AppColors.yellowLabel, onOpen: widget.onOpen),
                    const SizedBox(height: 40),
                  ],
                  _label('المفضلة', Icons.star),
                  if (favs.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: const Color(0x88100418),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: AppColors.purpleOutline.withOpacity(0.6), width: 2),
                      ),
                      child: const Text('اضغط ⭐ على أي فيلم ليظهر هنا وتصل إليه بسرعة.',
                          style: TextStyle(fontSize: 38, color: _lav, fontWeight: FontWeight.w500)),
                    )
                  else
                    SizedBox(
                      height: 400,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: favs.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 26),
                        itemBuilder: (_, i) => _MiniCard(film: favs[i], onOpen: widget.onOpen),
                      ),
                    ),
                  const SizedBox(height: 44),
                  if (today != null) ...[
                    _label('فيلم اليوم', Icons.wb_sunny),
                    _BigCard(film: today, button: 'شاهده', accent: const Color(0xFFFF6BE5), onOpen: widget.onOpen),
                    const SizedBox(height: 40),
                  ],
                  if (tags.isNotEmpty) ...[
                    _label('اقتراحات اليوم لك', Icons.local_fire_department),
                    Wrap(
                      spacing: 18,
                      runSpacing: 18,
                      children: [for (final t in tags) _TagChip(tag: t, onTap: () => widget.onTag(t))],
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _label(String t, IconData icon) => Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 16),
        child: Row(children: [
          Icon(icon, color: AppColors.yellowLabel, size: 52),
          const SizedBox(width: 14),
          Text(t, style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
      );
}

class _BigCard extends StatelessWidget {
  final Map<String, dynamic> film;
  final String button;
  final Color accent;
  final OpenFilm onOpen;
  const _BigCard({required this.film, required this.button, required this.accent, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final tags = _tags(film).take(3).join(' • ');
    final year = (film['release_year'] ?? '').toString();
    return Stack(
      children: [
        GlowButton(
          onTap: () => onOpen(film, null),
          child: Container(
            height: 440,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFF7A0EA0), Color(0xFF1B0626)],
              ),
              borderRadius: BorderRadius.circular(44),
              border: Border.all(color: accent, width: 4),
              boxShadow: [BoxShadow(color: accent.withOpacity(0.28), blurRadius: 30)],
            ),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: SizedBox(width: 290, height: 396, child: NetImage(url: _poster(film), fit: BoxFit.cover)),
              ),
              const SizedBox(width: 30),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_title(film),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 62, height: 1.15, fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 12),
                    Text([if (tags.isNotEmpty) tags, if (year.isNotEmpty) year].join('  |  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 36, color: Color(0xFFE3B8FF), fontWeight: FontWeight.w500)),
                    const SizedBox(height: 26),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 14),
                      decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(40)),
                      child: Text(button,
                          style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w800, color: Colors.black)),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
        Positioned(top: 34, right: 34, child: FavStar(id: FilmConfig.key(film), size: 70)),
      ],
    );
  }
}

class _MiniCard extends StatelessWidget {
  final Map<String, dynamic> film;
  final OpenFilm onOpen;
  const _MiniCard({required this.film, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Column(children: [
        Stack(children: [
          GlowButton(
            onTap: () => onOpen(film, null),
            child: Container(
              width: 250,
              height: 330,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.purpleOutline, width: 3),
                boxShadow: [BoxShadow(color: AppColors.cardShadow.withOpacity(0.6), blurRadius: 18)],
              ),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(25), child: NetImage(url: _poster(film), fit: BoxFit.cover)),
            ),
          ),
          Positioned(top: 10, right: 10, child: FavStar(id: FilmConfig.key(film), size: 56)),
        ]),
        const SizedBox(height: 8),
        Text(_title(film),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: Colors.white)),
      ]),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String tag;
  final VoidCallback onTap;
  const _TagChip({required this.tag, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlowButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xB3100418),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: AppColors.purpleOutline, width: 3),
        ),
        child: Text('# $tag', style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w700, color: Color(0xFFE3B8FF))),
      ),
    );
  }
}
