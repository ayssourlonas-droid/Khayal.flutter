import 'package:flutter/material.dart' hide Text;
import 'l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// أجزاء مشغّل الأفلام — تقابل في جودوت:
///   SeekSlider (المنطقة الآمنة) ← [SafeSeekBar]    SeekFeedback.gd ← [SeekFeedback]
///   SeekPicker.gd ← [showSeekPicker]               SubtitleLabel.gd ← [SubtitleOverlay]
///   StylePanel.gd ← [SubtitleStylePanel]           Global.seek_skip_seconds ← [FilmPlayerPrefs]

/// 83:45 أو 1:23:45
String fmtTime(Duration d) {
  final t = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = t ~/ 3600, m = (t % 3600) ~/ 60, s = t % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// تفضيلات المشغّل المحفوظة على الجهاز.
class FilmPlayerPrefs {
  FilmPlayerPrefs._();

  static const skipOptions = [5, 10, 15, 20, 25, 30, 45, 60];

  static Future<int> loadSkip() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getInt('film_seek_skip') ?? 10;
      return skipOptions.contains(v) ? v : 10;
    } catch (_) {
      return 10;
    }
  }

  static Future<void> saveSkip(int v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('film_seek_skip', v);
    } catch (_) {}
  }

  static Future<String> loadLang(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(key) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> saveLang(String key, String v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(key, v);
    } catch (_) {}
  }

  /// موضع الاستئناف بالثواني (0 = لا يوجد).
  static Future<int> loadPos(String id) async {
    if (id.isEmpty) return 0;
    try {
      final p = await SharedPreferences.getInstance();
      return p.getInt('film_pos_$id') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> savePos(String id, int seconds) async {
    if (id.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      if (seconds <= 0) {
        await p.remove('film_pos_$id');
      } else {
        await p.setInt('film_pos_$id', seconds);
      }
    } catch (_) {}
  }
}

// ─────────────────────────── مظهر الترجمة ───────────────────────────

const kSubColors = <Color>[
  Colors.white,
  Color(0xFFFFEB3B),
  Color(0xFF80DEEA),
  Color(0xFFA5D6A7),
  Color(0xFFFFB74D),
  Color(0xFFF48FB1),
];

class SubStyle {
  final int colorIndex;
  final double size; // حجم الخط
  final double opacity; // شفافية الخلفية
  final bool sharp; // حواف حادة أو مقوّسة

  const SubStyle({this.colorIndex = 0, this.size = 26, this.opacity = 0.6, this.sharp = true});

  Color get color => kSubColors[colorIndex.clamp(0, kSubColors.length - 1).toInt()];

  SubStyle copyWith({int? colorIndex, double? size, double? opacity, bool? sharp}) => SubStyle(
        colorIndex: colorIndex ?? this.colorIndex,
        size: size ?? this.size,
        opacity: opacity ?? this.opacity,
        sharp: sharp ?? this.sharp,
      );

  static Future<SubStyle> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return SubStyle(
        colorIndex: p.getInt('film_sub_color') ?? 0,
        size: p.getDouble('film_sub_size') ?? 26,
        opacity: p.getDouble('film_sub_opacity') ?? 0.6,
        sharp: p.getBool('film_sub_sharp') ?? true,
      );
    } catch (_) {
      return const SubStyle();
    }
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('film_sub_color', colorIndex);
      await p.setDouble('film_sub_size', size);
      await p.setDouble('film_sub_opacity', opacity);
      await p.setBool('film_sub_sharp', sharp);
    } catch (_) {}
  }
}

/// نص الترجمة فوق الفيديو (يقابل SubtitleLabel.gd).
class SubtitleOverlay extends StatelessWidget {
  final String text;
  final SubStyle style;
  const SubtitleOverlay({super.key, required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(style.opacity),
        borderRadius: BorderRadius.circular(style.sharp ? 0 : 16),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: style.color,
          fontSize: style.size,
          height: 1.3,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

/// لافتة إعدادات مظهر الترجمة (تقابل StylePanel.gd): اللون، حجم الخط، الشفافية، الحواف.
class SubtitleStylePanel extends StatelessWidget {
  final SubStyle style;
  final ValueChanged<SubStyle> onChanged;
  final VoidCallback onClose;
  const SubtitleStylePanel({super.key, required this.style, required this.onChanged, required this.onClose});

  @override
  Widget build(BuildContext context) {
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text(t,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 16, decoration: TextDecoration.none, fontWeight: FontWeight.w600)),
        );
    return Material(
      color: const Color(0xEE14091F),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Expanded(
                  child: Text('مظهر الترجمة',
                      style: TextStyle(
                          color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, decoration: TextDecoration.none)),
                ),
                IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded, color: Colors.white)),
              ]),
              label('اللون'),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (var i = 0; i < kSubColors.length; i++)
                  GestureDetector(
                    onTap: () => onChanged(style.copyWith(colorIndex: i)),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: kSubColors[i],
                        shape: BoxShape.circle,
                        border: Border.all(color: style.colorIndex == i ? const Color(0xFFE040FB) : Colors.white24, width: 3),
                      ),
                    ),
                  ),
              ]),
              label('حجم الخط'),
              Slider(
                min: 14,
                max: 44,
                value: style.size.clamp(14.0, 44.0).toDouble(),
                onChanged: (v) => onChanged(style.copyWith(size: v)),
              ),
              label('شفافية الخلفية'),
              Slider(
                min: 0,
                max: 1,
                value: style.opacity.clamp(0.0, 1.0).toDouble(),
                onChanged: (v) => onChanged(style.copyWith(opacity: v)),
              ),
              label('شكل الخلفية'),
              Wrap(spacing: 10, children: [
                ChoiceChip(
                    label: const Text('حادة'), selected: style.sharp, onSelected: (_) => onChanged(style.copyWith(sharp: true))),
                ChoiceChip(
                    label: const Text('مقوّسة'),
                    selected: !style.sharp,
                    onSelected: (_) => onChanged(style.copyWith(sharp: false))),
              ]),
              label('معاينة'),
              Center(child: SubtitleOverlay(text: 'نص الترجمة', style: style)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── التقديم والرجوع ───────────────────────────

/// شريط التقديم بـ«منطقة آمنة» (كما في VideoUI.gd): أي لمسة تبعد عن المؤشر أكثر من [safeZone]
/// من طول الشريط تُهمل، فلا يقفز الفيلم بلمسة خاطئة. اسحب المؤشر أو المسه من قريب.
class SafeSeekBar extends StatefulWidget {
  final double ratio; // 0..1 الموضع الحالي (أو موضع السحب)
  final double buffered; // 0..1 المحمَّل مسبقاً
  final bool enabled;
  final double safeZone;
  final VoidCallback onStart;
  final ValueChanged<double> onUpdate;
  final ValueChanged<double> onEnd;

  const SafeSeekBar({
    super.key,
    required this.ratio,
    required this.buffered,
    required this.enabled,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    this.safeZone = 0.10,
  });

  @override
  State<SafeSeekBar> createState() => _SafeSeekBarState();
}

class _SafeSeekBarState extends State<SafeSeekBar> {
  bool _active = false;
  double _last = 0;

  double _r(double dx, double w) => w <= 0 ? 0.0 : (dx / w).clamp(0.0, 1.0).toDouble();

  @override
  Widget build(BuildContext context) {
    final ratio = widget.ratio.clamp(0.0, 1.0).toDouble();
    final buffered = widget.buffered.clamp(0.0, 1.0).toDouble();
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          if (!widget.enabled) return;
          final r = _r(d.localPosition.dx, w);
          if ((r - ratio).abs() > widget.safeZone) return; // خارج المنطقة الآمنة
          widget.onStart();
          widget.onEnd(r);
        },
        onHorizontalDragStart: (d) {
          if (!widget.enabled) return;
          final r = _r(d.localPosition.dx, w);
          if ((r - ratio).abs() > widget.safeZone) {
            _active = false;
            return;
          }
          _active = true;
          _last = ratio;
          widget.onStart();
        },
        onHorizontalDragUpdate: (d) {
          if (!_active) return;
          _last = _r(d.localPosition.dx, w);
          widget.onUpdate(_last);
        },
        onHorizontalDragEnd: (_) {
          if (!_active) return;
          _active = false;
          widget.onEnd(_last);
        },
        onHorizontalDragCancel: () {
          if (!_active) return;
          _active = false;
          widget.onEnd(_last);
        },
        child: SizedBox(
          height: 56,
          child: Stack(
            alignment: Alignment.centerLeft,
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
              ),
              Container(
                width: w * buffered,
                height: 8,
                decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(4)),
              ),
              Container(
                width: w * ratio,
                height: 8,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF9C27B0), Color(0xFFE040FB)]),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Positioned(
                left: (w * ratio) - 14,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE066),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: const Color(0xFFE040FB).withOpacity(0.6), blurRadius: 12)],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _HalfCirclePainter extends CustomPainter {
  final bool forward;
  _HalfCirclePainter(this.forward);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(forward ? size.width : 0, size.height / 2);
    canvas.drawCircle(center, size.height * 0.55, Paint()..color = Colors.white.withOpacity(0.2));
  }

  @override
  bool shouldRepaint(covariant _HalfCirclePainter old) => old.forward != forward;
}

/// تأثير نصف دائرة شفّاف عند التقديم/الرجوع بالنقر المزدوج (يقابل SeekFeedback.gd).
class SeekFeedback extends StatelessWidget {
  final bool visible;
  final bool forward;
  final int seconds;
  const SeekFeedback({super.key, required this.visible, required this.forward, required this.seconds});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _HalfCirclePainter(forward)),
            Align(
              alignment: Alignment(forward ? 0.72 : -0.72, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded, size: 46, color: Colors.white),
                  Text('$seconds ثواني',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.none,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(1, 2))])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// نافذة اختيار مدة التقديم بعجلة سحب (تقابل SeekPicker.gd): الرقم المتمركز هو المختار.
Future<int?> showSeekPicker(BuildContext context, int current) {
  const options = FilmPlayerPrefs.skipOptions;
  var sel = options.contains(current) ? current : 10;
  final ctl = FixedExtentScrollController(initialItem: options.indexOf(sel));
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          backgroundColor: const Color(0xF014091F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: const BorderSide(color: Color(0xFFB000A8), width: 3),
          ),
          child: SizedBox(
            width: 300,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('مدة التقديم والرجوع',
                      style: TextStyle(
                          color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, decoration: TextDecoration.none)),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 150,
                    child: ListWheelScrollView.useDelegate(
                      controller: ctl,
                      itemExtent: 52,
                      diameterRatio: 1.7,
                      physics: const FixedExtentScrollPhysics(),
                      onSelectedItemChanged: (i) => setState(() => sel = options[i]),
                      childDelegate: ListWheelChildListDelegate(children: [
                        for (final o in options)
                          Center(
                            child: Text(
                              '$o',
                              style: TextStyle(
                                fontSize: o == sel ? 40 : 24,
                                fontWeight: FontWeight.w800,
                                color: o == sel ? const Color(0xFFFFD633) : Colors.white54,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: () => Navigator.pop(ctx, sel), child: const Text('موافق')),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
