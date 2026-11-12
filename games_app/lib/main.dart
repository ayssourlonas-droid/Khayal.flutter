import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'error_reporter.dart';
import 'loading_screen.dart';
import 'nav.dart';
import 'sound_fx.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorReporter.install(); // سجل أخطاء مجهول يظهر في تطبيق المتحكم
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]); // orientation=1 في جودوت
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await SoundFx.instance.init();
  runApp(const GameHubApp());
}

class GameHubApp extends StatelessWidget {
  const GameHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GameHub',
      debugShowCheckedModeBanner: false,
      navigatorKey: Nav.navKey,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
        splashFactory: NoSplash.splashFactory,
      ),
      // الواجهة الجذرية من اليمين لليسار كما في جودوت
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const LoadingScreen(),
    );
  }
}
