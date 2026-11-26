import 'package:flutter/material.dart' hide Text;

import 'l10n.dart';

/// تصنيف سريع في الدرج الجانبي. التصفية تطابق أي وسم يحتوي على واحد من [aliases] (بحروف صغيرة).
/// عدّل القوائم هنا لتطابق أسماء الوسوم الفعلية في بياناتك (category_tags).
class SideCat {
  final String key;
  final String label;
  final IconData icon; // أيقونة مؤقتة حتى تجهز الصور
  final List<String> aliases;
  const SideCat(this.key, this.label, this.icon, this.aliases);

  bool matches(List<String> tags) {
    for (final t in tags) {
      final low = t.toLowerCase();
      for (final a in aliases) {
        if (low.contains(a.toLowerCase())) return true;
      }
    }
    return false;
  }
}

class SideCats {
  SideCats._();

  // وسوم الألعاب في khayal.data هي وسوم GitHub إنجليزية (arcade, endless-runner, card-game ...)
  static const games = <SideCat>[
    SideCat('action', 'أكشن', Icons.flash_on_rounded,
        ['action', 'shoot', 'fps', 'fight', 'أكشن', 'اكشن', 'حركة', 'zombie']),
    SideCat('arcade', 'أركيد', Icons.videogame_asset_rounded,
        ['arcade', 'runner', 'breakout', 'frogger', 'snake', 'atari', 'platformer', 'flappy', 'أركيد', 'اركيد']),
    SideCat('puzzle', 'ألغاز', Icons.extension_rounded,
        ['puzzle', 'bubble', 'match', '2048', 'sudoku', 'logic', 'brain', 'ألغاز', 'لغز']),
    SideCat('cards', 'ورق وطاولة', Icons.style_rounded,
        ['card', 'board-game', 'chess', 'checkers', 'poker', 'domino', 'ورق', 'طاولة', 'شطرنج']),
    SideCat('strategy', 'استراتيجية', Icons.shield_rounded,
        ['strategy', 'builder', 'tower', 'defense', 'tycoon', 'simulation', 'idle', 'استراتيج', 'بناء']),
  ];

  static const films = <SideCat>[
    SideCat('drama', 'دراما', Icons.movie_filter_rounded, ['drama', 'دراما']),
    SideCat('comedy', 'كوميديا', Icons.mood_rounded, ['comedy', 'كوميد']),
    SideCat('scifi', 'خيال', Icons.rocket_launch_rounded, ['sci-fi', 'scifi', 'science fiction', 'fantasy', 'خيال']),
    SideCat('animation', 'رسوم', Icons.animation_rounded, ['animation', 'animated', 'رسوم', 'كرتون', 'أنيميشن']),
    SideCat('documentary', 'وثائقي', Icons.public_rounded, ['documentary', 'وثائق']),
  ];

  static SideCat? byKey(List<SideCat> list, String key) {
    for (final c in list) {
      if (c.key == key) return c;
    }
    return null;
  }

  /// true إن كان [key] فارغاً (بلا تصفية) أو طابقت الوسوم التصنيف.
  static bool pass(List<SideCat> list, String key, List<String> tags) {
    if (key.isEmpty) return true;
    final c = byKey(list, key);
    return c == null || c.matches(tags);
  }
}

/// درج جانبي على الحافة اليمنى: خط رفيع يدل على أنه قابل للسحب، ويظهر كاملاً عند السحب نحو اليسار
/// (أو بنقرة على الخط). يُوضع مباشرة داخل Stack. [visible] = false يخفيه ويغلقه (للصفحة الرئيسية).
class SideCatsDrawer extends StatefulWidget {
  final double top;
  final bool visible;
  final List<SideCat> cats;
  final String selected;
  final ValueChanged<String> onSelect; // '' = إلغاء التصفية

  const SideCatsDrawer({
    super.key,
    required this.top,
    required this.visible,
    required this.cats,
    required this.selected,
    required this.onSelect,
  });

  @override
  State<SideCatsDrawer> createState() => _SideCatsDrawerState();
}

class _SideCatsDrawerState extends State<SideCatsDrawer> {
  static const _panelW = 170.0;
  static const _handleW = 36.0;
  static const _btnH = 96.0;
  static const _gap = 12.0;
  bool _open = false;
  double _drag = 0;

  @override
  void didUpdateWidget(covariant SideCatsDrawer old) {
    super.didUpdateWidget(old);
    if (!widget.visible && _open) _open = false;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _drag += d.delta.dx;
    if (_drag < -24 && !_open) {
      setState(() => _open = true);
      _drag = 0;
    } else if (_drag > 24 && _open) {
      setState(() => _open = false);
      _drag = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.cats.length;
    final panelH = n * _btnH + (n - 1) * _gap;
    return Positioned(
      right: 0,
      top: widget.top,
      width: _panelW + _handleW,
      height: panelH,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: AnimatedOpacity(
          opacity: widget.visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // اللوحة
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                right: _open ? _handleW : -_panelW,
                top: 0,
                width: _panelW,
                height: panelH,
                child: GestureDetector(
                  onHorizontalDragUpdate: _onDragUpdate,
                  child: Column(
                    children: [
                      for (var i = 0; i < n; i++) ...[
                        if (i > 0) const SizedBox(height: _gap),
                        _btn(widget.cats[i]),
                      ],
                    ],
                  ),
                ),
              ),
              // المقبض: خط رفيع على الحافة
              Positioned(
                right: 0,
                top: 0,
                width: _handleW,
                height: panelH,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => setState(() => _open = !_open),
                  onHorizontalDragUpdate: _onDragUpdate,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      width: 8,
                      height: 150,
                      decoration: BoxDecoration(
                        color: widget.selected.isEmpty ? Colors.white60 : const Color(0xFFE040FB),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: const [BoxShadow(color: Color(0x99E040FB), blurRadius: 12)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btn(SideCat c) {
    final sel = widget.selected == c.key;
    return GestureDetector(
      onTap: () {
        widget.onSelect(sel ? '' : c.key); // نقرة ثانية على المختار تلغي التصفية
        setState(() => _open = false);
      },
      child: Container(
        width: _panelW,
        height: _btnH,
        decoration: BoxDecoration(
          color: const Color(0xDD14091F),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: sel ? const Color(0xFFE040FB) : Colors.white24, width: sel ? 5 : 2),
          boxShadow: sel ? const [BoxShadow(color: Color(0x99E040FB), blurRadius: 16)] : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(c.icon, size: 46, color: sel ? const Color(0xFFFFE066) : Colors.white),
            Text(c.label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
          ],
        ),
      ),
    );
  }
}
