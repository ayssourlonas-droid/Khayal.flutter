import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// شاشة رسم بالإصبع لتحديد أماكن النصوص المراد إزالتها (Cloudinary Generative Remove).
/// كل خط ترسمه (دائرة حول النص أو تظليل فوقه) يتحول إلى مستطيل يحيط به، وتُرسل المستطيلات إلى Cloudinary.
/// ترجع سلسلة التحويل (مثل `e_gen_remove:region_((x_..;y_..;w_..;h_..))`) أو null عند الإلغاء.
class TextRemoveScreen extends StatefulWidget {
  final String imageUrl; // رابط المعاينة الحالية (إحداثيات المناطق تخصّ أبعاد هذه الصورة)
  const TextRemoveScreen({super.key, required this.imageUrl});
  @override
  State<TextRemoveScreen> createState() => _TextRemoveScreenState();
}

class _TextRemoveScreenState extends State<TextRemoveScreen> {
  final List<List<Offset>> _strokes = [];
  ui.Image? _img;
  String? _err;

  @override
  void initState() {
    super.initState();
    final stream = NetworkImage(widget.imageUrl).resolve(const ImageConfiguration());
    late ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      if (mounted) setState(() => _img = info.image);
      stream.removeListener(l);
    }, onError: (e, _) {
      if (mounted) setState(() => _err = 'تعذّر تحميل الصورة (قد تكون النسخة المعالجة غير جاهزة بعد؛ أعد المحاولة بعد لحظات).');
      stream.removeListener(l);
    });
    stream.addListener(l);
  }

  Rect _fitRect(Size box) {
    final iw = _img!.width.toDouble(), ih = _img!.height.toDouble();
    final s = (box.width / iw) < (box.height / ih) ? box.width / iw : box.height / ih;
    final w = iw * s, h = ih * s;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  String? _chain(Rect fit) {
    final iw = _img!.width.toDouble(), ih = _img!.height.toDouble();
    final k = iw / fit.width;
    final parts = <String>[];
    for (final s in _strokes) {
      if (s.length < 2) continue;
      var minX = s.first.dx, maxX = s.first.dx, minY = s.first.dy, maxY = s.first.dy;
      for (final p in s) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
      const pad = 6.0; // هامش بسيط بوحدات الشاشة
      final l = ((minX - pad - fit.left) * k).clamp(0, iw - 1).toDouble();
      final t = ((minY - pad - fit.top) * k).clamp(0, ih - 1).toDouble();
      final r = ((maxX + pad - fit.left) * k).clamp(1, iw).toDouble();
      final b = ((maxY + pad - fit.top) * k).clamp(1, ih).toDouble();
      final w = (r - l).round(), h = (b - t).round();
      if (w < 8 || h < 8) continue;
      parts.add('(x_${l.round()};y_${t.round()};w_$w;h_$h)');
    }
    if (parts.isEmpty) return null;
    return 'e_gen_remove:region_(${parts.join(';')})';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إزالة النصوص — ارسم حول النص')),
      body: _err != null
          ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_err!)))
          : _img == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Expanded(
                    child: LayoutBuilder(builder: (context, c) {
                      final box = Size(c.maxWidth, c.maxHeight);
                      _lastBox = box;
                      final fit = _fitRect(box);
                      return GestureDetector(
                        onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
                        onPanUpdate: (d) => setState(() => _strokes.last.add(d.localPosition)),
                        child: Stack(children: [
                          Positioned.fromRect(rect: fit, child: Image.network(widget.imageUrl, fit: BoxFit.fill)),
                          Positioned.fill(child: CustomPaint(painter: _StrokePainter(_strokes))),
                        ]),
                      );
                    }),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Text(
                      'ارسم دائرة أو ظلّل فوق كل نص. كل خط يصبح مستطيلاً يحيط به ثم يُملأ تلقائياً. اجعل المستطيل بقدر النص ولا تتجاوزه كثيراً.',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Wrap(spacing: 8, runSpacing: 6, children: [
                      OutlinedButton.icon(
                          onPressed: _strokes.isEmpty ? null : () => setState(_strokes.removeLast),
                          icon: const Icon(Icons.undo),
                          label: const Text('تراجع')),
                      OutlinedButton.icon(
                          onPressed: _strokes.isEmpty ? null : () => setState(_strokes.clear),
                          icon: const Icon(Icons.delete_sweep),
                          label: const Text('مسح')),
                      OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context, 'e_gen_remove:prompt_text'),
                          icon: const Icon(Icons.auto_fix_high),
                          label: const Text('كل النصوص تلقائياً')),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _strokes.isEmpty ? null : _applyFromRender,
                        child: const Padding(padding: EdgeInsets.all(12), child: Text('إزالة المناطق المحددة')),
                      ),
                    ),
                  ),
                ]),
    );
  }

  Size _lastBox = Size.zero;

  void _applyFromRender() {
    // مستطيل عرض الصورة بنفس مقاييس منطقة الرسم عند آخر بناء
    final fit = _fitRect(_lastBox);
    final chain = _chain(fit);
    if (chain == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الخطوط صغيرة جداً؛ ارسم حول النص بوضوح.')));
      return;
    }
    Navigator.pop(context, chain);
  }
}

class _StrokePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _StrokePainter(this.strokes);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xCCFF4081)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in strokes) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final o in s.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) => true;
}
