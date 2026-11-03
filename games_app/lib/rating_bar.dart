import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'ui_image.dart';

/// ساعة مشتركة لحركة الشريط (يقابل TIME في tape_movement.gdshader) —
/// تُشغَّل فقط ما دام هناك مستمعون.
class TapeClock extends ChangeNotifier {
  TapeClock._() {
    _ticker = Ticker((d) {
      seconds = d.inMicroseconds / 1e6;
      notifyListeners();
    });
  }
  static final TapeClock instance = TapeClock._();
  late final Ticker _ticker;
  double seconds = 0;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (!_ticker.isActive) _ticker.start();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners && _ticker.isActive) _ticker.stop();
  }
}

/// شريط تقييم بالنجوم: شريط ملوّن متحرك (scroll_speed 0.2) يظهر فقط داخل قناع النجوم،
/// وخلفه نجوم باهتة. يقابل TextureProgressBar + tape_movement.gdshader.
class RatingBar extends StatefulWidget {
  final double value; // 0..max
  final double max;
  final double width;
  final double height;
  final String tapeAsset; // صورة الشريط الملوّن
  final String maskAsset; // قناع النجوم
  final Color bgTint;
  final double scrollSpeed;

  const RatingBar({
    super.key,
    required this.value,
    required this.width,
    required this.height,
    required this.tapeAsset,
    required this.maskAsset,
    this.max = 10,
    this.bgTint = const Color.fromRGBO(184, 121, 189, 0.494), // (0.722,0.4736,0.74,0.494)
    this.scrollSpeed = 0.2,
  });

  @override
  State<RatingBar> createState() => _RatingBarState();
}

class _RatingBarState extends State<RatingBar> {
  ui.Image? _tape;
  ui.Image? _mask;

  @override
  void initState() {
    super.initState();
    AssetUiImages.load(widget.tapeAsset).then((i) {
      if (mounted) setState(() => _tape = i);
    });
    AssetUiImages.load(widget.maskAsset).then((i) {
      if (mounted) setState(() => _mask = i);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: (_tape == null || _mask == null)
          ? const SizedBox.shrink()
          : CustomPaint(
              painter: _RatingPainter(
                tape: _tape!,
                mask: _mask!,
                fraction: (widget.value / widget.max).clamp(0.0, 1.0),
                tint: widget.bgTint,
                speed: widget.scrollSpeed,
                clock: TapeClock.instance,
              ),
            ),
    );
  }
}

class _RatingPainter extends CustomPainter {
  final ui.Image tape, mask;
  final double fraction, speed;
  final Color tint;
  final TapeClock clock;

  _RatingPainter({
    required this.tape,
    required this.mask,
    required this.fraction,
    required this.tint,
    required this.speed,
    required this.clock,
  }) : super(repaint: clock);

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    final maskSrc = Rect.fromLTWH(0, 0, mask.width.toDouble(), mask.height.toDouble());
    final tapeSrc = Rect.fromLTWH(0, 0, tape.width.toDouble(), tape.height.toDouble());

    // 1) النجوم الباهتة (الخلفية)
    canvas.drawImageRect(mask, maskSrc, dst, Paint()..colorFilter = ColorFilter.mode(tint, BlendMode.srcIn));

    // 2) الشريط المتحرك مقصوص بنسبة التقدم ثم مقنّع بالنجوم
    canvas.saveLayer(dst, Paint());
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * fraction, size.height));
    final shift = (clock.seconds * speed) % 1.0; // fract(UV.x + TIME*speed)
    final off = -shift * size.width;
    for (var k = 0; k < 3; k++) {
      canvas.drawImageRect(
        tape,
        tapeSrc,
        Rect.fromLTWH(off + k * size.width, 0, size.width, size.height),
        Paint(),
      );
    }
    canvas.restore();
    canvas.drawImageRect(mask, maskSrc, dst, Paint()..blendMode = BlendMode.dstIn);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RatingPainter old) =>
      old.fraction != fraction || old.tape != tape || old.mask != mask;
}
