import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/colors.dart';
import 'shader_cache.dart';

/// يقابل NetLoader.gd + net_loader.gdshader: مؤشر وايفاي/بيانات بشيدر GPU.
/// [loading] = false يخفيه بتلاشٍ ناعم (0.5 ثانية) ثم يزيله من الشجرة.
class NetLoader extends StatefulWidget {
  final double width;
  final double height;
  final bool loading;
  final Color baseColor;
  final Color pulseColor;
  final Color bgOverlay;
  final bool fade;

  const NetLoader({
    super.key,
    required this.width,
    required this.height,
    this.loading = true,
    this.baseColor = Colors.white,
    this.pulseColor = AppColors.netPulse,
    this.bgOverlay = const Color.fromRGBO(26, 26, 26, 0.7),
    this.fade = true,
  });

  @override
  State<NetLoader> createState() => _NetLoaderState();
}

class _NetLoaderState extends State<NetLoader> with SingleTickerProviderStateMixin {
  ui.FragmentProgram? _program;
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);
  double _blend = 0; // 0 = وايفاي، 1 = بيانات
  bool _isData = false;
  Timer? _checkTimer;
  Duration _last = Duration.zero;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    ShaderCache.load('shaders/net_loader.frag').then((p) {
      if (mounted) setState(() => _program = p);
    });
    _detect();
    _blend = _isData ? 1 : 0;
    _checkTimer = Timer.periodic(const Duration(seconds: 1), (_) => _detect());
    _ticker = createTicker((d) {
      final dt = (d - _last).inMicroseconds / 1e6;
      _last = d;
      final target = _isData ? 1.0 : 0.0;
      _blend += (target - _blend) * (5.0 * dt).clamp(0.0, 1.0); // transition_speed = 5
      _time.value = d.inMicroseconds / 1e6;
    });
    if (widget.loading) _ticker.start();
  }

  Future<void> _detect() async {
    if (!Platform.isAndroid) return;
    try {
      final ifs = await NetworkInterface.list();
      var wifi = false;
      for (final i in ifs) {
        if (i.name.toLowerCase().contains('wlan') && i.addresses.isNotEmpty) {
          wifi = true;
          break;
        }
      }
      _isData = !wifi;
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant NetLoader old) {
    super.didUpdateWidget(old);
    if (widget.loading && !_ticker.isActive) {
      _gone = false;
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return SizedBox(width: widget.width, height: widget.height);
    final child = SizedBox(
      width: widget.width,
      height: widget.height,
      child: _program == null
          ? const SizedBox.shrink()
          : CustomPaint(
              painter: _NetPainter(
                program: _program!,
                time: _time,
                blend: () => _blend,
                base: widget.baseColor,
                pulse: widget.pulseColor,
                bg: widget.bgOverlay,
              ),
            ),
    );
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: widget.loading ? 1 : 0,
        duration: widget.fade ? const Duration(milliseconds: 500) : Duration.zero,
        curve: Curves.easeInOutSine,
        onEnd: () {
          if (!widget.loading && mounted) {
            _ticker.stop();
            setState(() => _gone = true);
          }
        },
        child: child,
      ),
    );
  }
}

class _NetPainter extends CustomPainter {
  final ui.FragmentProgram program;
  final ValueNotifier<double> time;
  final double Function() blend;
  final Color base, pulse, bg;

  _NetPainter({
    required this.program,
    required this.time,
    required this.blend,
    required this.base,
    required this.pulse,
    required this.bg,
  }) : super(repaint: time);

  void _color(ui.FragmentShader s, int i, Color c) {
    s.setFloat(i, c.red / 255);
    s.setFloat(i + 1, c.green / 255);
    s.setFloat(i + 2, c.blue / 255);
    s.setFloat(i + 3, c.alpha / 255);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final s = program.fragmentShader();
    s.setFloat(0, size.width);
    s.setFloat(1, size.height);
    s.setFloat(2, time.value);
    s.setFloat(3, blend());
    s.setFloat(4, size.width / size.height);
    _color(s, 5, base);
    _color(s, 9, pulse);
    _color(s, 13, bg);
    canvas.drawRect(Offset.zero & size, Paint()..shader = s);
  }

  @override
  bool shouldRepaint(covariant _NetPainter old) => true;
}
