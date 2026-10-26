import 'package:flutter/material.dart';
import 'core/store.dart';
import 'core/theme.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Game Control',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const HomeScreen(),
    );
  }
}
