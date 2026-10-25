import 'package:flutter/material.dart';

import '../core/colors.dart';

/// يقابل TitleMarquee.gd: العنوان يتحرك ذهاباً وإياباً فقط إن لم يتسع بالمساحة
/// (كان شيدر moving_the_title مفقوداً من المشروع الأصلي، فهذا التنفيذ يعمل فعلاً).
class TitleMarquee extends StatefulWidget {
  final String text;
  final double width;
  final double height;
  final double fontSize;
  const TitleMarquee({
    super.key,
    required this.text,
    required this.width,
    required this.height,
    this.fontSize = 30,
  });

  @override
  State<TitleMarquee> createState() => _TitleMarqueeState();
}

class _TitleMarqueeState extends State<TitleMarquee> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  double _overflow = 0;

  TextStyle get _style => TextStyle(fontSize: widget.fontSize, color: Colors.white);

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void didUpdateWidget(covariant TitleMarquee old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _measure();
  }

  void _measure() {
    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: _style),
      textDirection: TextDirection.rtl,
      maxLines: 1,
    )..layout();
    _overflow = (tp.width - widget.width).clamp(0.0, double.infinity);
    _c.stop();
    if (_overflow > 0) {
      // سرعة ثابتة تقريبية؛ انتظار 1 ث في كل طرف (wait_time)
      final ms = (_overflow / 0.2 / 5.0 * 10).clamp(1500.0, 8000.0).round();
      _c.duration = Duration(milliseconds: ms);
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _outlined(String t) => Stack(children: [
        Text(t,
            maxLines: 1,
            softWrap: false,
            style: _style.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 6
                  ..strokeJoin = StrokeJoin.round
                  ..color = AppColors.purpleOutline)),
        Text(t, maxLines: 1, softWrap: false, style: _style),
      ]);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRect(
        child: _overflow <= 0
            ? Center(child: _outlined(widget.text))
            : AnimatedBuilder(
                animation: _c,
                builder: (_, __) {
                  final t = Curves.easeInOut.transform(_c.value);
                  return OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    child: Transform.translate(
                      offset: Offset(-_overflow * t, 0),
                      child: _outlined(widget.text),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
