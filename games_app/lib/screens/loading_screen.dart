import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/ads_manager.dart';
import '../core/colors.dart';
import '../core/data_repository.dart';
import '../core/player_points.dart';
import '../widgets/design.dart';
import '../widgets/nav.dart';
import 'home_screen.dart';

/// يقابل LoadingScreen.gd — تدرج + شعار + جملة عشوائية + شريط تقدم ناعم (حد أدنى 3.5 ث).
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> with SingleTickerProviderStateMixin {
  static const _messages = [
    'العب الآن.. ألعاب ممتعة في جيبك.',
    'جاري تجهيز مكتبة الألعاب...',
    'تحدَّ نفسك، وحطّم رقمك القياسي!',
    'ألعاب خفيفة تعمل مباشرة بلا تحميل.',
    'ابحث عن لعبتك المفضلة وابدأ اللعب.',
    'هل جربت لعبة جديدة اليوم؟',
    'مجموعة ألعاب تتجدد باستمرار.',
    'شاهد إعلاناً قصيراً لتحصل على نقطة لعب.',
    'نحترم حقوق المطورين.. كل لعبة مذكور مطوّرها ورخصتها.',
    'جاري جلب آخر الألعاب المضافة...',
    'استرخِ.. نحن نجهّز لك المتعة.',
    'هل واجهت مشكلة؟ تواصل معنا من الإعدادات.',
    'رأيك يهمنا.. ساعدنا في تحسين التطبيق.',
    'هل تعلم؟ يمكنك تغيير الثيم من الإعدادات.',
    'المتعة تبدأ الآن.. شكراً لانتظارك.',
  ];

  late final String _msg = _messages[Random().nextInt(_messages.length)];
  late final Ticker _ticker;
  double _smooth = 0; // 0..100
  double _real = 0; // 0..100
  bool _minTimePassed = false;
  bool _gone = false;
  Duration _last = Duration.zero;
  double _textOpacity = 0;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) setState(() => _textOpacity = 1);
    });
    Future.delayed(const Duration(milliseconds: 3500), () => _minTimePassed = true);
    _ticker = createTicker(_tick)..start();
    _work();
  }

  Future<void> _work() async {
    await PlayerPoints.instance.load();
    _real = 30;
    AdsManager.instance.init(); // لا ننتظره: التهيئة تجري بالخلفية
    _real = 60;
    try {
      await DataRepository.load('movie', (g, {required fromNetwork}) {})
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    _real = 100;
  }

  void _tick(Duration d) {
    final dt = (d - _last).inMicroseconds / 1e6;
    _last = d;
    // لا يتجاوز الشريط نسبة الوقت المنقضي من الحد الأدنى 3.5 ث
    final timeCap = (d.inMilliseconds / 3500 * 100).clamp(0.0, 100.0);
    final target = min(_real, timeCap);
    setState(() => _smooth += (target - _smooth) * (2 * dt).clamp(0.0, 1.0));
    if (!_gone && _minTimePassed && _real >= 100 && _smooth >= 98) {
      _gone = true;
      _ticker.stop();
      Nav.replace(const HomeScreen());
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GodotGradientBox(
        loadingGradient,
        child: Design(
          builder: (context, h) => Stack(
            children: [
              // الشعار 500x700 على بعد 300 من الأعلى
              Positioned(
                top: 300,
                left: (1080 - 500) / 2,
                width: 500,
                height: 700,
                child: Image.asset('assets/images/a1a.webp', fit: BoxFit.contain),
              ),
              // شريط التقدم 900x50
              Positioned(
                top: h - 450,
                left: 90,
                width: 900,
                height: 50,
                child: _ProgressBar(value: _smooth / 100),
              ),
              // الجملة
              Positioned(
                top: h - 350,
                left: 40,
                width: 1000,
                height: 50,
                child: AnimatedOpacity(
                  opacity: _textOpacity,
                  duration: const Duration(seconds: 1),
                  child: Text(
                    _msg,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 32,
                      color: Color.fromRGBO(18, 0, 15, 1),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double value;
  const _ProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: Color.fromRGBO(60, 4, 33, 0.78))),
          Align(
            alignment: Alignment.centerRight, // RTL: يمتلئ من اليمين
            child: FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color.fromRGBO(153, 0, 199, 0.93),
                      Colors.white,
                    ],
                    stops: [0, 0.95],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
