import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/app_state.dart';

/// يقابل PageScroll.gd: سحب للتحديث (عتبة 80، أقصى سحب 130، أيقونة a1p تدور 2→10 rad/s)،
/// ارتداد سفلي بهالة بيضاء شعاعية (300x120)، مهلة أمان 20 ث، وحجب النقرات 400 ms بعد التحديث.
class PullRefreshScroll extends StatefulWidget {
  final List<Widget> slivers;
  final Future<void> Function() onRefresh;
  final ScrollController? controller;
  final VoidCallback? onNearBottom;
  final double nearBottomPx;

  const PullRefreshScroll({
    super.key,
    required this.slivers,
    required this.onRefresh,
    this.controller,
    this.onNearBottom,
    this.nearBottomPx = 300,
  });

  @override
  State<PullRefreshScroll> createState() => _PullRefreshScrollState();
}

class _PullRefreshScrollState extends State<PullRefreshScroll> with SingleTickerProviderStateMixin {
  static const double threshold = 80;
  static const double maxPull = 130;
  static const double maxBottom = 60;

  double _pull = 0;
  double _bottom = 0;
  bool _refreshing = false;
  double _angle = 0;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      final dt = (d - _last).inMicroseconds / 1e6;
      _last = d;
      final speed = _refreshing ? 10.0 : 2.0 + 8.0 * (_pull / threshold).clamp(0.0, 1.0);
      setState(() => _angle += speed * dt);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    final m = n.metrics;
    if (n is ScrollUpdateNotification || n is OverscrollNotification) {
      final top = m.pixels < m.minScrollExtent ? (m.minScrollExtent - m.pixels) : 0.0;
      final bot = m.pixels > m.maxScrollExtent ? (m.pixels - m.maxScrollExtent) : 0.0;
      if (top != _pull.clamp(0.0, maxPull) || bot != _bottom) {
        setState(() {
          _pull = math.min(top, maxPull);
          _bottom = math.min(bot, maxBottom);
        });
      }
      if (widget.onNearBottom != null && m.maxScrollExtent - m.pixels < widget.nearBottomPx) {
        widget.onNearBottom!();
      }
    }
    if (n is ScrollEndNotification) {
      final pulled = _pull >= threshold;
      if (pulled && !_refreshing) _startRefresh();
      if (!_refreshing) {
        setState(() {
          _pull = 0;
          _bottom = 0;
        });
      } else {
        setState(() => _bottom = 0);
      }
    }
    return false;
  }

  Future<void> _startRefresh() async {
    setState(() {
      _refreshing = true;
      _pull = 0;
    });
    try {
      await widget.onRefresh().timeout(const Duration(seconds: 20)); // مهلة أمان
    } catch (_) {}
    AppState.inputCooldownUntilMs = DateTime.now().millisecondsSinceEpoch + 400;
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final iconY = _refreshing ? 20.0 : (_pull.clamp(0.0, maxPull) - 100);
    final iconVisible = _refreshing || _pull > 4;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: CustomScrollView(
            controller: widget.controller,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: _refreshing ? 110 : 0,
                ),
              ),
              ...widget.slivers,
            ],
          ),
        ),
        if (iconVisible)
          Positioned(
            top: iconY,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: _refreshing ? 1 : (_pull / threshold).clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: _angle,
                    child: Image.asset('assets/images/a1p.webp', width: 100, height: 100),
                  ),
                ),
              ),
            ),
          ),
        if (_bottom > 1)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: (_bottom / maxBottom).clamp(0.0, 1.0),
                  child: Container(
                    width: 300,
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [Colors.white.withOpacity(0.55), Colors.white.withOpacity(0)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
