import 'package:flutter/material.dart';
import 'consts.dart';
import 'github.dart';
import 'theme.dart';
import 'ui.dart';
import 'game_form_screen.dart';
import 'actions_api.dart';

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

  /// إخفاء لعبة منشورة عن اللاعبين: تُنقل إلى «للمراجعة» (لا تُحذف ولا تُحذف ملفاتها من الاستضافة).
  Future<void> _hide(Map<String, dynamic> g) async {
    final title = '${_m(g['main_scene'])['title_ar'] ?? '?'}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إخفاء اللعبة؟'),
        content: Text('«$title» ستختفي عن اللاعبين فوراً وتنتقل إلى «للمراجعة». يمكنك اعتمادها لاحقاً من هناك.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إخفاء')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      final id = '${g['id']}';
      // نقرأ الحالي من GitHub (لا نعتمد على النسخة القديمة في الذاكرة)
      final pf = await Github.getJson(pendingFile);
      final pending = Github.asList(pf.data);
      final entry = Map<String, dynamic>.from(g);
      entry['review_note'] = 'أُخفيت يدوياً من تطبيق المتحكم';
      if (!pending.any((e) => '${e['id']}' == id)) pending.add(entry);
      // 1) الإضافة أولاً: لو فشلت الخطوة التالية تبقى اللعبة ظاهرة (لا تضيع)
      await Github.putJson(pendingFile, pending, sha: pf.sha, message: 'hide game #$id -> pending');
      for (final file in [gamesFile, featuredFile]) {
        final f = await Github.getJson(file);
        final list = Github.asList(f.data);
        final n = list.length;
        list.removeWhere((e) => '${e['id']}' == id);
        if (list.length != n) {
          await Github.putJson(file, list, sha: f.sha, message: 'hide game #$id from $file');
        }
      }
      if (mounted) toast(context, 'أُخفيت اللعبة ✓ (في «للمراجعة»)');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    await _load();
  }

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
        bottom: TabBar(controller: _tabs, indicatorColor: Pal.lime, labelColor: Pal.lime, unselectedLabelColor: Colors.white70, tabs: [
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

  /// يعيد "طبخ" اللعبة بأحدث نسخة من أدوات المعالجة: يجلب المستودع الأصلي من جديد ويُشغّل import-game.yml.
  /// publish.py يتعرّف على اللعبة من source_url فيحدّث ملفاتها فقط دون المساس بسجلها (الاسم، التقييم، التصنيفات...).
  Future<void> _reimport(Map<String, dynamic> g) async {
    final d = _m(g['details_scene']);
    final url = '${d['source_url'] ?? ''}'.trim();
    final name = '${_m(g['main_scene'])['title_ar'] ?? '?'}';
    if (!url.startsWith('https://github.com/')) {
      toast(context, 'لا يوجد رابط مصدر على GitHub لهذه اللعبة، لا يمكن إعادة استيرادها.', error: true);
      return;
    }
    final o = '${d['orientation'] ?? ''}';
    if (!await confirm(
        context,
        'إعادة الاستيراد',
        'سيُجلب "$name" من مصدرها الأصلي ويُعاد فحصها وبناؤها بأحدث أدوات المعالجة، وتُستبدل ملفاتها فقط. '
            'بياناتها (الاسم، الوصف، التصنيفات، التقييم) تبقى كما هي. ولن تُحفظ إعدادات الاستيراد اليدوية السابقة (مجلد/أمر بناء مخصصان).',
        ok: 'أعد الاستيراد')) return;
    try {
      await ActionsApi.dispatch('import-game.yml', {
        'repo_url': url,
        'orientation': (o == 'portrait' || o == 'landscape' || o == 'both') ? o : 'portrait',
        'auto_publish': 'no',
        'prune': 'smart',
        'media': 'safe',
        'ai_test': 'no',
      });
      if (mounted) toast(context, 'بدأت إعادة الاستيراد ✓ تابع النتيجة في تبويب السجل بصفحة الاستيراد');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Widget _card(Map<String, dynamic> g) {
    final main = _m(g['main_scene']);
    final d = _m(g['details_scene']);
    final poster = '${main['poster_url'] ?? ''}';
    final why = validateGame(g);
    return Card(
      color: Pal.surface,
      shape: Pal.cardShape(why.isEmpty ? null : Pal.warn),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 52,
            height: 52,
            child: poster.startsWith('http')
                ? Image.network(poster, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image))
                : const Icon(Icons.videogame_asset),
          ),
        ),
        title: Text('${main['title_ar'] ?? '?'}'),
        subtitle: Text(
          '#${g['id']} · ★ ${main['app_rating'] ?? 0} · ${g['release_year'] ?? ''} · ${d['license'] ?? '-'}'
          '${why.isEmpty ? '' : '\n⚠️ $why'}',
          style: TextStyle(color: why.isEmpty ? null : Pal.warn),
        ),
        isThreeLine: why.isNotEmpty,
        trailing: _tabs.index == 2
            ? IconButton(
                tooltip: 'إعادة الاستيراد من المصدر',
                icon: const Icon(Icons.refresh, color: Pal.lime),
                onPressed: () => _reimport(g),
              )
            : PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'hide') _hide(g);
                  if (v == 'reimport') _reimport(g);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'reimport', child: Text('إعادة الاستيراد من المصدر')),
                  PopupMenuItem(value: 'hide', child: Text('إخفاء حتى المراجعة')),
                ],
              ),
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
