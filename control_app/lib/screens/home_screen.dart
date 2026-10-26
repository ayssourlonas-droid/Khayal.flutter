import 'package:flutter/material.dart';
import '../core/store.dart';
import '../core/theme.dart';
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
  Future<void> _go(Widget w) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    if (mounted) setState(() {});
  }

  Widget _tile(IconData icon, String title, String sub, List<Color> colors, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(colors: colors, begin: Alignment.topRight, end: Alignment.bottomLeft),
            boxShadow: [BoxShadow(color: colors.last.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              child: Row(children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
                  child: Icon(icon, size: 30, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 3),
                    Text(sub, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8))),
                  ]),
                ),
                const Icon(Icons.chevron_left, color: Colors.white70),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A0A3A), Pal.bg],
            stops: [0, 0.45],
          ),
        ),
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(18, 20, 18, 24), children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: Pal.headerGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Pal.magenta.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Row(children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(18)),
                  child: const Icon(Icons.sports_esports, size: 36, color: Pal.lime),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Game Control', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
                    SizedBox(height: 4),
                    Text('إدارة ألعاب خيال', style: TextStyle(fontSize: 14, color: Colors.white70)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            if (!Store.hasGithub)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Pal.warn.withOpacity(0.12),
                  border: Border.all(color: Pal.warn.withOpacity(0.6)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded, color: Pal.warn),
                  SizedBox(width: 10),
                  Expanded(child: Text('ابدأ من الإعدادات: أدخل GitHub Token (وCloudinary لرفع الصور).')),
                ]),
              ),
            _tile(Icons.add_circle, 'إضافة لعبة جديدة', 'نموذج كامل مع فحص الرخصة',
                const [Color(0xFF7B1FA2), Color(0xFFAD00BA)], () => _go(const GameFormScreen())),
            _tile(Icons.edit_note, 'تعديل الألعاب', 'القائمة، المميزة، وللمراجعة',
                const [Color(0xFF4527A0), Color(0xFF7C4DFF)], () => _go(const GamesListScreen())),
            _tile(Icons.cloud_upload, 'الإصدار وروابط الدعم', 'version.json ومحرر JSON',
                const [Color(0xFF00695C), Color(0xFF26A69A)], () => _go(const ServerScreen())),
            _tile(Icons.settings, 'الإعدادات', 'GitHub وCloudinary',
                const [Color(0xFF37474F), Color(0xFF607D8B)], () => _go(const SettingsScreen())),
          ]),
        ),
      ),
    );
  }
}
