import 'package:flutter/material.dart';
import '../core/store.dart';
import 'game_form_screen.dart';
import 'games_list_screen.dart';
import 'server_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Widget _btn(IconData i, String t, VoidCallback f) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: SizedBox(
          width: double.infinity,
          height: 72,
          child: FilledButton.icon(
            onPressed: f,
            icon: Icon(i, size: 30),
            label: Text(t, style: const TextStyle(fontSize: 20)),
          ),
        ),
      );

  Future<void> _go(Widget w) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('متحكم الألعاب')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        if (!Store.hasGithub)
          Card(
            color: Colors.orange.shade900,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('ابدأ من الإعدادات: أدخل GitHub Token (وCloudinary لرفع الصور).'),
            ),
          ),
        const SizedBox(height: 10),
        _btn(Icons.add_circle, 'إضافة لعبة جديدة', () => _go(const GameFormScreen())),
        _btn(Icons.edit_note, 'تعديل الألعاب', () => _go(const GamesListScreen())),
        _btn(Icons.cloud_upload, 'الإصدار والمحرر (version.json)', () => _go(const ServerScreen())),
        _btn(Icons.settings, 'الإعدادات', () => _go(const SettingsScreen())),
      ]),
    );
  }
}
