import 'package:flutter/material.dart';
import 'consts.dart';
import 'github.dart';
import 'theme.dart';
import 'ui.dart';
import 'actions_screen.dart';
import 'game_form_screen.dart';
import 'games_list_screen.dart';

/// مركز الألعاب: كل ما يخص الألعاب في مكان واحد (إضافة، تعديل، مراجعة، استيراد، بحث شامل).
class GamesHubScreen extends StatefulWidget {
  const GamesHubScreen({super.key});
  @override
  State<GamesHubScreen> createState() => _GamesHubScreenState();
}

class _GamesHubScreenState extends State<GamesHubScreen> {
  List<Map<String, dynamic>> _games = [];
  List<Map<String, dynamic>> _featured = [];
  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _games = Github.asList((await Github.getJson(gamesFile)).data);
      _featured = Github.asList((await Github.getJson(featuredFile)).data);
      _pending = Github.asList((await Github.getJson(pendingFile)).data);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Map _m(dynamic v) => v is Map ? v : {};

  Future<void> _go(Widget w) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    if (mounted) _load();
  }

  Widget _count(String label, int n, Color c, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: c.withOpacity(0.14),
            border: Border.all(color: c.withOpacity(0.6)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: [
            Text(_loading ? '…' : '$n', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12.5)),
          ]),
        ),
      ),
    );
  }

  Widget _action(IconData icon, String title, String sub, Color c, VoidCallback onTap, {String? badge}) {
    return Card(
      color: Pal.surface,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: c.withOpacity(0.2), child: Icon(icon, color: c)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12.5)),
        trailing: badge == null
            ? const Icon(Icons.chevron_left)
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(12)),
                child: Text(badge, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
        onTap: onTap,
      ),
    );
  }

  List<Widget> _results() {
    final q = _q.trim().toLowerCase();
    final out = <Widget>[];
    void add(List<Map<String, dynamic>> src, String label, Color c, bool feat, bool pend) {
      for (final g in src) {
        final main = _m(g['main_scene']);
        final t = '${main['title_ar'] ?? ''} ${main['title_en'] ?? ''} ${g['id']}'.toLowerCase();
        if (!t.contains(q)) continue;
        out.add(Card(
          color: Pal.surface,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text('${main['title_ar'] ?? '?'}'),
            subtitle: Text('#${g['id']} · ${main['title_en'] ?? ''}'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: c.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
              child: Text(label, style: TextStyle(color: c, fontSize: 12)),
            ),
            onTap: () => _go(GameFormScreen(item: g, isFeatured: feat, fromPending: pend)),
          ),
        ));
      }
    }

    add(_games, 'منشورة', Pal.lime, false, false);
    add(_featured, 'مميزة', Colors.amber, true, false);
    add(_pending, 'للمراجعة', Pal.warn, false, true);
    if (out.isEmpty) out.add(const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا توجد نتائج'))));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final searching = _q.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الألعاب'),
        actions: [IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 24), children: [
          TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search), hintText: 'ابحث في كل الألعاب (منشورة، مميزة، للمراجعة) بالاسم أو الرقم'),
          ),
          const SizedBox(height: 12),
          if (searching) ..._results() else ...[
            Row(children: [
              _count('منشورة', _games.length, Pal.lime, () => _go(const GamesListScreen(initialTab: 0))),
              const SizedBox(width: 8),
              _count('مميزة', _featured.length, Colors.amber, () => _go(const GamesListScreen(initialTab: 1))),
              const SizedBox(width: 8),
              _count('للمراجعة', _pending.length, Pal.warn, () => _go(const GamesListScreen(initialTab: 2))),
            ]),
            const SizedBox(height: 16),
            _action(Icons.add_circle, 'إضافة لعبة جديدة', 'نموذج كامل مع فحص الرخصة', Pal.magenta,
                () => _go(const GameFormScreen())),
            _action(Icons.edit_note, 'تعديل الألعاب', 'المنشورة والمميزة، مع إخفاء وإعادة استيراد', const Color(0xFF7C4DFF),
                () => _go(const GamesListScreen(initialTab: 0))),
            _action(Icons.rule, 'ألعاب للمراجعة', 'اعتماد أو تعديل أو إعادة استيراد الألعاب المستوردة', Pal.warn,
                () => _go(const GamesListScreen(initialTab: 2)),
                badge: _pending.isEmpty ? null : '${_pending.length}'),
            _action(Icons.rocket_launch, 'استيراد الألعاب', 'استيراد من GitHub، اكتشاف، وسجل النتائج الملونة',
                const Color(0xFFFF9800), () => _go(const ActionsScreen())),
          ],
        ]),
      ),
    );
  }
}
