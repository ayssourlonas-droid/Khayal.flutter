import 'package:flutter/material.dart';

import '../core/colors.dart';

/// يقابل SceneTransition.gd: انتقال بتلاشٍ إلى لون داكن ثم ظهور (0.3 ث لكل نصف).
/// مع قفل يمنع تكرار الانتقال أثناء تنفيذ انتقال سابق.
class Nav {
  Nav._();
  static final navKey = GlobalKey<NavigatorState>();
  static bool _busy = false;

  static Route<T> _route<T>(Widget page, double speed) {
    final ms = (300 / (speed <= 0 ? 1 : speed)).round().clamp(80, 900).toInt();
    return PageRouteBuilder<T>(
      transitionDuration: Duration(milliseconds: ms * 2),
      reverseTransitionDuration: Duration(milliseconds: ms * 2),
      opaque: true,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (ctx, anim, sec, child) {
        // النصف الأول: الشاشة القديمة تتلاشى إلى اللون الداكن، الثاني: الجديدة تظهر
        final v = anim.value;
        final cover = v < 0.5 ? (v * 2) : (1 - (v - 0.5) * 2);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (v >= 0.5) child,
            IgnorePointer(
              child: ColoredBox(color: AppColors.transitionFade.withOpacity(cover.clamp(0.0, 1.0))),
            ),
          ],
        );
      },
    );
  }

  /// الانتقال إلى شاشة جديدة (push)
  static Future<T?> push<T>(Widget page, {double speed = 1}) async {
    if (_busy) return null;
    _busy = true;
    final f = navKey.currentState!.push<T>(_route<T>(page, speed));
    Future.delayed(const Duration(milliseconds: 150), () => _busy = false);
    return f;
  }

  /// استبدال الشاشة الحالية
  static Future<T?> replace<T>(Widget page, {double speed = 1}) async {
    if (_busy) return null;
    _busy = true;
    final f = navKey.currentState!.pushReplacement<T, void>(_route<T>(page, speed));
    Future.delayed(const Duration(milliseconds: 150), () => _busy = false);
    return f;
  }

  /// العودة لأول شاشة (الرئيسية)
  static void popToRoot() => navKey.currentState?.popUntil((r) => r.isFirst);

  static void pop() => navKey.currentState?.maybePop();
}
