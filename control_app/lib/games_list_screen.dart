import 'package:flutter/material.dart';
import 'consts.dart';
import 'github.dart';
import 'theme.dart';
import 'ui.dart';
import 'game_form_screen.dart';
import 'games_pane.dart';
import 'seen_games.dart';

/// شاشة الألعاب (المنشورة | المميزة | للمراجعة). المحتوى في games_pane.dart.
class GamesListScreen extends StatefulWidget {
  final int initialTab; // 0 المنشورة، 1 المميزة، 2 للمراجعة
  const GamesListScreen({super.key, this.initialTab = 0});
  @override
  State<GamesListScreen> createState() => _GamesListScreenState();
}

class _GamesListScreenState extends State<GamesListScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2));
  List<Map<String, dynamic>> _games = [];
  List<Map<String, dynamic>> _featured = [];
  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (mounted && !_tabs.indexIsChanging) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await SeenGames.load();
      _games = Github.asList((await Github.getJson(gamesFile)).data);
      _featured = Github.asList((await Github.getJson(featuredFile)).data);
      _pending = Github.asList((await Github.getJson(pendingFile)).data);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  int _unseen(List<Map<String, dynamic>> l) => l.where((g) => SeenGames.badge(g) != null).length;

  Tab _tab(String t, List<Map<String, dynamic>> l) {
    final u = _unseen(l);
    return Tab(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$t (${l.length})'),
      if (u > 0) ...[const SizedBox(width: 6), Badge(label: Text('$u'), backgroundColor: Pal.lime, textColor: Colors.black)],
    ]));
  }

  Widget _pane(int i) => GamesPane(
        tab: i,
        games: _games,
        featured: _featured,
        pending: _pending,
        loading: _loading,
        onReload: _load,
        onSeenChanged: () => setState(() {}),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الألعاب'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Pal.lime,
          labelColor: Pal.lime,
          unselectedLabelColor: Colors.white70,
          tabs: [_tab('المنشورة', _games), _tab('المميزة', _featured), _tab('للمراجعة', _pending)],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const GameFormScreen()));
          _load();
        },
        child: const Icon(Icons.add),
      ),
      body: TabBarView(controller: _tabs, children: [_pane(0), _pane(1), _pane(2)]),
    );
  }
}
