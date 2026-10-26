import 'package:flutter/material.dart';
import '../core/consts.dart';
import '../core/github.dart';
import '../widgets/ui.dart';
import 'game_form_screen.dart';

class GamesListScreen extends StatefulWidget {
  const GamesListScreen({super.key});
  @override
  State<GamesListScreen> createState() => _GamesListScreenState();
}

class _GamesListScreenState extends State<GamesListScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  List<Map<String, dynamic>> _games = [];
  List<Map<String, dynamic>> _featured = [];
  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;
  String _q = '';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final g = await Github.getJson(gamesFile);
      final f = await Github.getJson(featuredFile);
      _games = Github.asList(g.data);
      _featured = Github.asList(f.data);
      _pending = Github.asList((await Github.getJson(pendingFile)).data);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Map _m(dynamic v) => v is Map ? v : {};

  List<Map<String, dynamic>> get _shown {
    final src = _tabs.index == 0 ? _games : (_tabs.index == 1 ? _featured : _pending);
    return src.where((g) {
      final main = _m(g['main_scene']);
      final t = '${main['title_ar'] ?? ''} ${main['title_en'] ?? ''}'.toLowerCase();
      if (_q.isNotEmpty && !t.contains(_q.toLowerCase())) return false;
      final rating = double.tryParse('${main['app_rating'] ?? 0}') ?? 0;
      final year = int.tryParse('${g['release_year'] ?? 0}') ?? 0;
      switch (_filter) {
        case 'top':
          return rating >= 8;
        case 'new':
          return year >= 2020;
        case 'bad':
          return validateGame(g).isNotEmpty;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _shown;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الألعاب'),
        bottom: TabBar(controller: _tabs, tabs: [
          Tab(text: 'الألعاب (${_games.length})'),
          Tab(text: 'المميزة (${_featured.length})'),
          Tab(text: 'للمراجعة (${_pending.length})'),
        ]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const GameFormScreen()));
          _load();
        },
        child: const Icon(Icons.add),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث بالاسم'),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _filter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('الكل')),
                DropdownMenuItem(value: 'top', child: Text('★8+')),
                DropdownMenuItem(value: 'new', child: Text('2020+')),
                DropdownMenuItem(value: 'bad', child: Text('غير صالحة')),
              ],
              onChanged: (v) => setState(() => _filter = v ?? 'all'),
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: list.isEmpty
                      ? ListView(children: const [SizedBox(height: 120), Center(child: Text('لا توجد ألعاب'))])
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) => _card(list[i]),
                        ),
                ),
        ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> g) {
    final main = _m(g['main_scene']);
    final d = _m(g['details_scene']);
    final poster = '${main['poster_url'] ?? ''}';
    final why = validateGame(g);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: SizedBox(
          width: 52,
          child: poster.startsWith('http')
              ? Image.network(poster, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image))
              : const Icon(Icons.videogame_asset),
        ),
        title: Text('${main['title_ar'] ?? '?'}'),
        subtitle: Text(
          '#${g['id']} · ★ ${main['app_rating'] ?? 0} · ${g['release_year'] ?? ''} · ${d['license'] ?? '-'}'
          '${why.isEmpty ? '' : '\n⚠️ $why'}',
          style: TextStyle(color: why.isEmpty ? null : Colors.orangeAccent),
        ),
        isThreeLine: why.isNotEmpty,
        onTap: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => GameFormScreen(
                        item: g,
                        isFeatured: _featured.any((f) => '${f['id']}' == '${g['id']}'),
                        fromPending: _tabs.index == 2,
                      )));
          _load();
        },
      ),
    );
  }
}
