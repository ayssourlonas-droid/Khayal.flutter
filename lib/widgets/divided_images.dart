import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'ui_image.dart';

/// يقابل divided_into_3_images.gdshader: حتى 3 صور مقسومة بخطوط نيون قطرية.
/// (نسخة CustomPainter — الشيدر الأصلي كان يحتاج قياس القوام ومسارات متعددة، والرسم هنا أدق وأخف.)
/// ملاحظة: الشيدر الأصلي لم يكن يقصّ كل صورة بمنطقتها فتغطي الأولى البقية؛
/// هنا تُقصّ كل صورة بمنطقتها حسب التصميم المقصود:
///   1 صورة: كاملة. 2: مثلث علوي أيسر + مثلث سفلي أيمن. 3: الثانية والثالثة تتقاسمان المثلث السفلي.
class DividedImages extends StatefulWidget {
  final List<String> urls;
  final double width, height;
  const DividedImages({super.key, required this.urls, required this.width, required this.height});

  @override
  State<DividedImages> createState() => _DividedImagesState();
}

class _DividedImagesState extends State<DividedImages> {
  late List<ui.Image?> _imgs = List.filled(widget.urls.length.clamp(0, 3).toInt(), null);

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _imgs.length; i++) {
      BytesUiImages.fromUrl(widget.urls[i]).then((img) {
        if (mounted && img != null) setState(() => _imgs[i] = img);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: CustomPaint(painter: _DividedPainter(List.of(_imgs), _imgs.length)),
    );
  }
}

class _DividedPainter extends CustomPainter {
  final List<ui.Image?> imgs;
  final int count;
  _DividedPainter(this.imgs, this.count);

  void _drawCover(Canvas c, ui.Image img, Size s, Path clip) {
    c.save();
    c.clipPath(clip);
    final ia = img.width / img.height;
    final ra = s.width / s.height;
    Rect src;
    if (ia > ra) {
      final w = img.height * ra;
      src = Rect.fromLTWH((img.width - w) / 2, 0, w, img.height.toDouble());
    } else {
      final h = img.width / ra;
      src = Rect.fromLTWH(0, (img.height - h) / 2, img.width.toDouble(), h);
    }
    c.drawImageRect(img, src, Offset.zero & s, Paint()..filterQuality = FilterQuality.medium);
    c.restore();
  }

  Path _poly(Size s, List<Offset> uv) {
    final p = Path()..moveTo(uv[0].dx * s.width, uv[0].dy * s.height);
    for (final o in uv.skip(1)) {
      p.lineTo(o.dx * s.width, o.dy * s.height);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (count == 0) return;
    final full = Path()..addRect(Offset.zero & size);
    if (count == 1) {
      if (imgs[0] != null) _drawCover(canvas, imgs[0]!, size, full);
      return;
    }
    final a = _poly(size, const [Offset(0, 0), Offset(1, 0), Offset(0, 1)]);
    if (imgs[0] != null) _drawCover(canvas, imgs[0]!, size, a);

    if (count == 2) {
      final b = _poly(size, const [Offset(1, 0), Offset(1, 1), Offset(0, 1)]);
      if (imgs[1] != null) _drawCover(canvas, imgs[1]!, size, b);
    } else {
      final right = _poly(size, const [Offset(1, 0), Offset(1, 1), Offset(0.5, 1), Offset(0.5, 0.5)]);
      final left = _poly(size, const [Offset(0.5, 0.5), Offset(0.5, 1), Offset(0, 1)]);
      if (imgs[1] != null) _drawCover(canvas, imgs[1]!, size, right);
      if (imgs[2] != null) _drawCover(canvas, imgs[2]!, size, left);
    }

    // خطوط النيون: لون (0.5,0,1)، سماكة 0.02، توهج 2.0
    const neon = Color.fromRGBO(128, 0, 255, 1);
    final w = size.width * 0.04;
    final glow = Paint()
      ..color = neon.withOpacity(0.9)
      ..strokeWidth = w * 1.8
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final core = Paint()
      ..color = neon
      ..strokeWidth = w * 0.6
      ..style = PaintingStyle.stroke;
    final main = [Offset(size.width, 0), Offset(0, size.height)];
    canvas.drawLine(main[0], main[1], glow);
    canvas.drawLine(main[0], main[1], core);
    if (count == 3) {
      final s0 = Offset(size.width * 0.5, size.height * 0.5);
      final s1 = Offset(size.width * 0.5, size.height);
      canvas.drawLine(s0, s1, glow);
      canvas.drawLine(s0, s1, core);
    }
  }

  @override
  bool shouldRepaint(covariant _DividedPainter old) => true;
}
