import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'shader_cache.dart';

/// يقابل ButtonGlow.gd + the_buttons_glow.gdshader.
/// يغلّف أي ودجت: عند اللمس تظهر موجة توهج (0.5 ث، تقدّم 0→1.4، دمج إضافي) ثم يُستدعى [onTap].
class GlowButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  const GlowButton({super.key, required this.child, this.onTap, this.color = Colors.white});

  @override
  State<GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<GlowButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  late final Animation<double> _t =
      Tween<double>(begin: 0, end: 1.4).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutQuad));
  ui.FragmentProgram? _program;
  Offset _uv = const Offset(0.5, 0.5);

  @override
  void initState() {
    super.initState();
    ShaderCache.load('shaders/button_glow.frag').then((p) {
      if (mounted) setState(() => _program = p);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent e) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final s = box.size;
    _uv = Offset(e.localPosition.dx / s.width, e.localPosition.dy / s.height);
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (_program != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _GlowPainter(_program!, _t, () => _uv, widget.color, _c),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  final ui.FragmentProgram program;
  final Animation<double> progress;
  final Offset Function() uv;
  final Color color;
  final AnimationController ctl;
  _GlowPainter(this.program, this.progress, this.uv, this.color, this.ctl) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !ctl.isAnimating) return; // خامد قبل أي ضغطة
    final s = program.fragmentShader();
    final p = uv();
    s.setFloat(0, size.width);
    s.setFloat(1, size.height);
    s.setFloat(2, ctl.lastElapsedDuration?.inMicroseconds.toDouble() ?? 0);
    s.setFloat(3, progress.value);
    s.setFloat(4, p.dx);
    s.setFloat(5, p.dy);
    s.setFloat(6, 0.2); // thickness
    s.setFloat(7, 1.2); // sparkle_intensity
    s.setFloat(8, color.red / 255);
    s.setFloat(9, color.green / 255);
    s.setFloat(10, color.blue / 255);
    s.setFloat(11, color.alpha / 255);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = s
        ..blendMode = BlendMode.plus, // render_mode blend_add
    );
  }

  @override
  bool shouldRepaint(covariant _GlowPainter old) => true;
}
