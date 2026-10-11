import 'package:flutter/material.dart';

/// ألوان وتدرجات منقولة حرفياً من ملفات .tscn (الألوان والزينات تبقى كما هي).
class AppColors {
  AppColors._();

  static const purpleOutline = Color.fromRGBO(173, 0, 186, 1); // (0.68,0,0.73)
  static const cardShadow = Color.fromRGBO(179, 21, 161, 1); // (0.7007,0.0807,0.6319)
  static const cardOutline = Color.fromRGBO(173, 0, 186, 1);
  static const yellowLabel = Color.fromRGBO(231, 255, 20, 1); // (0.906,1,0.078)
  static const titleRed = Color.fromRGBO(255, 36, 36, 1); // (1,0.14,0.14)
  static const transitionFade = Color.fromRGBO(12, 3, 17, 1); // (0.0455,0.0107,0.0669)
  static const gameBg = Color.fromRGBO(13, 8, 23, 1); // (0.05,0.03,0.09)
  static const netPulse = Color(0xFF4B0082);
  static const popupBorder = Color.fromRGBO(179, 77, 230, 1); // (0.7,0.3,0.9)
}

Color _c(double r, double g, double b, [double a = 1]) =>
    Color.fromRGBO((r * 255).round(), (g * 255).round(), (b * 255).round(), a);

/// تدرج شاشة التحميل + التفاصيل + مشغل الصوت (قطري من (0,0) إلى (1,1)).
final loadingGradient = _Spec.linear(
  const Offset(0, 0),
  const Offset(1, 1),
  const [0, 0.24263984, 1],
  [_c(0.10980392, 0, 0.10980392), _c(0.24854168, 0.1625, 0.25), _c(0.99607843, 0.8784314, 1)],
);

/// خلفية الصفحة الرئيسية (عمودي من الأسفل للأعلى: from(1,1) → to(1,0)).
final homeGradient = _Spec.linear(
  const Offset(1, 1),
  const Offset(1, 0),
  const [0, 0.043243203, 0.10405401, 0.17837834, 0.825455, 0.89459455, 0.89628375, 0.89797294, 1],
  [
    _c(0, 0, 0),
    _c(0.026598431, 1.0596815e-05, 0.03154598),
    _c(0.36710557, 0.00057501806, 0.398606),
    _c(0, 0, 0),
    _c(0.17774718, 7.081447e-05, 0.21080975),
    _c(0.19673929, 7.838093e-05, 0.23333457),
    _c(0.10592347, 2.6763706e-05, 0.12931687),
    _c(0, 0, 0),
    _c(0.64426494, 0.0015242046, 0.8063243),
  ],
);

final settingsTopGradient = _Spec.radial(
  const Offset(0.5066669, 0.38358968),
  const Offset(0.5054406, 0.96820515),
  const [0, 0.41884094, 0.66521776, 0.83913076, 0.9043482, 1],
  [
    _c(0, 0, 0),
    _c(0.47995895, 0.00058401853, 0.5747885),
    _c(0.7332858, 0.0022494388, 0.9317852),
    _c(0.884776, 0.6340428, 1),
    _c(0.9613835, 0.8798598, 0.9615305),
    _c(1, 0.9434366, 0.9986095),
  ],
);

final settingsBodyGradient = _Spec.linear(
  const Offset(1, 1),
  const Offset(1, 0),
  const [0, 0.043243203, 0.10405401, 0.17837834, 0.52408797, 0.8598544, 0.9547449, 0.9941665, 1],
  [
    _c(0, 0, 0),
    _c(0.026598431, 1.0596815e-05, 0.03154598),
    _c(0.36710557, 0.00057501806, 0.398606),
    _c(0, 0, 0),
    _c(0.13617691, 4.414504e-05, 0.14838089),
    _c(0.26843718, 8.7020395e-05, 0.29249412),
    _c(0.16393787, 0.0009025418, 0.17839548),
    _c(0.28672102, 0.00016422212, 0.33680466),
    _c(1, 1, 1),
  ],
);

final settingsDecorGradient = _Spec.radial(
  const Offset(0.7230694, 0.73362833),
  const Offset(0.10973473, 0.11415924),
  const [0.42485237, 1],
  [_c(0.13934603, 6.3773245e-05, 0.47691184), _c(0.89439416, 0.83262295, 0.99999946)],
);

final audioCoverGradient = _Spec.radial(
  const Offset(0.5, 0.5),
  const Offset(0.6735852, 0.71132106),
  const [0, 0.3662921, 0.5310861, 0.71940297, 0.98805964],
  [
    _c(0.74, 0.06659998, 0.7287765),
    _c(0.74, 0.06659998, 0.7287765),
    _c(0.9329084, 0.87163943, 0.9306644),
    _c(1, 1, 1),
    _c(0, 0, 0, 0),
  ],
);

/// وصف تدرج بنفس دلالات GradientTexture2D في جودوت (إحداثيات UV بين 0 و 1).
class _Spec {
  final bool radial;
  final Offset from, to;
  final List<double> stops;
  final List<Color> colors;
  const _Spec(this.radial, this.from, this.to, this.stops, this.colors);
  factory _Spec.linear(Offset f, Offset t, List<double> s, List<Color> c) =>
      _Spec(false, f, t, s, c);
  factory _Spec.radial(Offset f, Offset t, List<double> s, List<Color> c) =>
      _Spec(true, f, t, s, c);
}

typedef GodotGradient = Object;

/// يرسم GradientTexture2D كما يفعل جودوت (مع تمدد على المستطيل بالكامل).
class GodotGradientBox extends StatelessWidget {
  final Object spec;
  final Widget? child;
  const GodotGradientBox(this.spec, {super.key, this.child});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _GradPainter(spec as _Spec), child: child);
}

class _GradPainter extends CustomPainter {
  final _Spec s;
  _GradPainter(this.s);

  List<double> _fixedStops(List<Color> outColors) {
    // جودوت يمدّ أول/آخر لون خارج النطاق؛ نضيف عقدتين عند 0 و 1 إن لزم.
    final st = List<double>.from(s.stops);
    final cs = List<Color>.from(s.colors);
    if (st.first > 0) {
      st.insert(0, 0);
      cs.insert(0, cs.first);
    }
    if (st.last < 1) {
      st.add(1);
      cs.add(cs.last);
    }
    outColors
      ..clear()
      ..addAll(cs);
    return st;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final colors = <Color>[];
    final stops = _fixedStops(colors);
    final unit = const Rect.fromLTWH(0, 0, 1, 1);
    final Shader shader;
    if (s.radial) {
      final r = (s.to - s.from).distance;
      shader = RadialGradient(
        center: Alignment(s.from.dx * 2 - 1, s.from.dy * 2 - 1),
        radius: r <= 0 ? 0.0001 : r,
        colors: colors,
        stops: stops,
      ).createShader(unit);
    } else {
      shader = LinearGradient(
        begin: Alignment(s.from.dx * 2 - 1, s.from.dy * 2 - 1),
        end: Alignment(s.to.dx * 2 - 1, s.to.dy * 2 - 1),
        colors: colors,
        stops: stops,
      ).createShader(unit);
    }
    canvas.save();
    canvas.scale(size.width, size.height);
    canvas.drawRect(unit, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GradPainter old) => old.s != s;
}
