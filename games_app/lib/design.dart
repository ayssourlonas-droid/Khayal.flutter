import 'package:flutter/material.dart';

/// أبعاد التصميم الأصلي في جودوت: 1080 عرضاً (الارتفاع يتبع نسبة الشاشة).
const double kDesignWidth = 1080;

/// يرسم [builder] على لوحة عرضها 1080 وحدة تصميم ويكبّرها لعرض الشاشة،
/// فتبقى كل الأبعاد (بكسل جودوت) كما هي حرفياً.
class Design extends StatelessWidget {
  final Widget Function(BuildContext context, double designHeight) builder;
  const Design({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : MediaQuery.of(context).size.width;
      final h = c.maxHeight.isFinite ? c.maxHeight : MediaQuery.of(context).size.height;
      final scale = w / kDesignWidth;
      final dh = h / scale;
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: kDesignWidth,
            height: dh,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
              child: Builder(builder: (ctx) => builder(ctx, dh)),
            ),
          ),
        ),
      );
    });
  }
}

/// نص بإطار خارجي (يقابل LabelSettings.outline في جودوت).
class OutlinedText extends StatelessWidget {
  final String text;
  final double size;
  final Color color;
  final Color outlineColor;
  final double outline;
  final TextAlign align;
  final int? maxLines;
  final TextOverflow? overflow;
  final double? height;

  const OutlinedText(
    this.text, {
    super.key,
    this.size = 30,
    this.color = Colors.white,
    this.outlineColor = const Color.fromRGBO(173, 0, 186, 1),
    this.outline = 0,
    this.align = TextAlign.center,
    this.maxLines,
    this.overflow,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final fill = Text(text,
        textAlign: align,
        maxLines: maxLines,
        overflow: overflow,
        style: TextStyle(
            fontSize: size, color: color, height: height, decoration: TextDecoration.none, fontWeight: FontWeight.normal));
    if (outline <= 0) return fill;
    final stroke = Text(text,
        textAlign: align,
        maxLines: maxLines,
        overflow: overflow,
        style: TextStyle(
          fontSize: size,
          height: height,
          decoration: TextDecoration.none,
          fontWeight: FontWeight.normal,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = outline * 2
            ..strokeJoin = StrokeJoin.round
            ..color = outlineColor,
        ));
    return Stack(alignment: Alignment.center, children: [stroke, fill]);
  }
}
