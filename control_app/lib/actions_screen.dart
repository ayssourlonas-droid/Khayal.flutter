import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'actions_api.dart';
import 'theme.dart';
import 'ui.dart';
import 'discover_tab.dart';
import 'import_verdict.dart';
import 'consts.dart';
import 'github.dart';
import 'games_pane.dart';
import 'games_list_screen.dart';
import 'game_form_screen.dart';
import 'seen_games.dart';

/// استيراد ألعاب الويب عبر GitHub Actions ومتابعة تشغيلاتها (نتيجة، أخطاء، إلغاء، إعادة).
class ActionsScreen extends StatefulWidget {
  final int initialTab; // 0 استيراد، 1 اكتشاف، 2 السجل، 3 للمراجعة، 4 الألعاب
  const ActionsScreen({super.key, this.initialTab = 0});
  @override
  State<ActionsScreen> createState() => _ActionsScreenState();
}

class _ActionsScreenState extends State<ActionsScreen> with TickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this, initialIndex: widget.initialTab.clamp(0, 4));
  List<Map<String, dynamic>> _games = [];
  List<Map<String, dynamic>> _featured = [];
  List<Map<String, dynamic>> _pending = [];
  bool _loadingGames = true;
  // تبويبات السجل الفرعية: المرفوضة | تحذيرات (الافتراضي) | نجحت
  late final TabController _logTabs = TabController(length: 3, vsync: this, initialIndex: 1);

  bool _busy = false;
  static const _wf = 'import-game.yml';

  // ── الاستيراد ──
  final repoUrl = TextEditingController();
  final tags = TextEditingController();
  final titleAr = TextEditingController();
  final subdir = TextEditingController();
  final buildCmd = TextEditingController();
  String orientation = 'portrait';
  bool autoPublish = false;
  String prune = 'smart';
  bool aiTest = false;
  bool media = true;
  final aiSteps = TextEditingController(text: '20');

  // ── السجل ──
  List<Map<String, dynamic>> _runs = [];
  bool _loadingRuns = true;
  static const _pageSize = 30;
  int _page = 1;
  bool _more = false;
  bool _loadingMore = false;
  String? _runsErr;
  Timer? _timer;
  final Map<int, Verdict> _verdicts = {};

  @override
  void initState() {
    super.initState();
    _loadRuns();
    _tabs.addListener(() {
      if (mounted && !_tabs.indexIsChanging) setState(() {});
    });
    _loadGames();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_runs.any((r) => r['status'] != 'completed')) _loadRuns(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _logTabs.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadGames() async {
    if (mounted) setState(() => _loadingGames = true);
    try {
      await SeenGames.load();
      _games = Github.asList((await Github.getJson(gamesFile)).data);
      _featured = Github.asList((await Github.getJson(featuredFile)).data);
      _pending = Github.asList((await Github.getJson(pendingFile)).data);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _loadingGames = false);
  }

  int _unseen(List<Map<String, dynamic>> l) => l.where((g) => SeenGames.badge(g) != null).length;

  Tab _gTab(String t, List<Map<String, dynamic>> l) {
    final u = _unseen(l);
    return Tab(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$t (${l.length})'),
      if (u > 0) ...[const SizedBox(width: 6), Badge(label: Text('$u'), backgroundColor: Pal.lime, textColor: Colors.black)],
    ]));
  }

  Widget _gPane(int i) => GamesPane(
        tab: i,
        games: _games,
        featured: _featured,
        pending: _pending,
        loading: _loadingGames,
        onReload: _loadGames,
        onSeenChanged: () => setState(() {}),
      );

  Future<void> _loadRuns({bool silent = false}) async {
    if (!silent) setState(() => _loadingRuns = true);
    try {
      final r = await ActionsApi.runs(_wf, n: _pageSize);
      if (mounted) setState(() {
        if (silent && _runs.length > r.length) {
          // تحديث دوري: نحدّث الصفحة الأولى فقط ونُبقي ما حُمّل من الأقدم
          final ids = {for (final x in r) x['id']};
          _runs = [...r, ..._runs.where((x) => !ids.contains(x['id']))];
        } else {
          _runs = r;
          _page = 1;
          _more = r.length >= _pageSize;
        }
        _runsErr = null;
      });
    } catch (e) {
      if (mounted) setState(() => _runsErr = '$e');
    }
    if (mounted) setState(() => _loadingRuns = false);
    _resolveVerdicts();
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final r = await ActionsApi.runs(_wf, n: _pageSize, page: _page + 1);
      if (mounted) {
        setState(() {
          final ids = {for (final x in _runs) x['id']};
          _runs = [..._runs, ...r.where((x) => !ids.contains(x['id']))];
          _page++;
          _more = r.length >= _pageSize;
        });
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _loadingMore = false);
    _resolveVerdicts();
  }

  /// يقرأ حكم كل تشغيل (بثلاثة طلبات متوازية كحد أقصى) ويخزّنه؛ المكتمل لا يُعاد جلبه.
  Future<void> _resolveVerdicts() async {
    final todo = [
      for (final r in _runs)
        if (ImportVerdicts.cached(r['id'] as int) == null || '${r['status']}' != 'completed') r
    ];
    var i = 0;
    Future<void> worker() async {
      while (i < todo.length) {
        final r = todo[i++];
        try {
          final v = await ImportVerdicts.resolve(r);
          if (mounted) setState(() => _verdicts[r['id'] as int] = v);
        } catch (_) {}
      }
    }

    await Future.wait([worker(), worker(), worker()]);
  }

  Future<void> _startImport() async {
    final url = repoUrl.text.trim();
    if (!url.startsWith('https://github.com/')) {
      toast(context, 'ضع رابط مستودع GitHub يبدأ بـ https://github.com/', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ActionsApi.dispatch(_wf, {
        'repo_url': url,
        'orientation': orientation,
        'auto_publish': autoPublish ? 'yes' : 'no',
        'prune': prune,
        'media': media ? 'safe' : 'off',
        'ai_test': aiTest ? 'yes' : 'no',
        if (aiTest) 'ai_steps': aiSteps.text.trim().isEmpty ? '20' : aiSteps.text.trim(),
        if (tags.text.trim().isNotEmpty) 'tags': tags.text.trim(),
        if (titleAr.text.trim().isNotEmpty) 'title_ar': titleAr.text.trim(),
        if (subdir.text.trim().isNotEmpty) 'subdir': subdir.text.trim(),
        if (buildCmd.text.trim().isNotEmpty) 'build_cmd': buildCmd.text.trim(),
      });
      if (mounted) toast(context, 'بدأ الاستيراد ✓');
      _tabs.animateTo(2);
      await Future.delayed(const Duration(seconds: 3));
      _loadRuns();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('استيراد وإدارة الألعاب'),
        actions: [
          IconButton(
            tooltip: 'الألعاب المميزة',
            icon: const Icon(Icons.star, color: Colors.amber, size: 22),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const GamesListScreen(initialTab: 1)));
              _loadGames();
            },
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadRuns();
              _loadGames();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: Pal.lime,
          labelColor: Pal.lime,
          unselectedLabelColor: Colors.white70,
          tabs: [
            const Tab(text: 'استيراد لعبة'),
            const Tab(text: 'اكتشاف'),
            const Tab(text: 'السجل'),
            _gTab('للمراجعة', _pending),
            _gTab('الألعاب', _games),
          ],
        ),
      ),
      floatingActionButton: _tabs.index >= 3
          ? FloatingActionButton(
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const GameFormScreen()));
                _loadGames();
              },
              child: const Icon(Icons.add),
            )
          : null,
      body: TabBarView(controller: _tabs, children: [
        _runTab(),
        DiscoverTab(onStarted: () => _loadRuns(silent: true)),
        _logTab(),
        _gPane(2),
        _gPane(0),
      ]),
    );
  }

  // ───────────── تبويب التشغيل ─────────────
  Widget _runTab() {
    return AbsorbPointer(
      absorbing: _busy,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        if (_busy) const LinearProgressIndicator(),
        _section('استيراد لعبة من GitHub', Icons.download_for_offline),
        field(repoUrl, 'رابط مستودع اللعبة', hint: 'https://github.com/owner/repo', type: TextInputType.url),
        DropdownButtonFormField<String>(
          value: orientation,
          decoration: const InputDecoration(labelText: 'اتجاه الشاشة'),
          items: const [
            DropdownMenuItem(value: 'portrait', child: Text('portrait')),
            DropdownMenuItem(value: 'landscape', child: Text('landscape')),
            DropdownMenuItem(value: 'both', child: Text('both')),
          ],
          onChanged: (v) => setState(() => orientation = v ?? orientation),
        ),
        DropdownButtonFormField<String>(
          value: prune,
          decoration: const InputDecoration(labelText: 'تقليل الملفات'),
          items: const [
            DropdownMenuItem(value: 'smart', child: Text('ذكي: حذف غير اللازم مع تحقق بالتجربة (موصى به)')),
            DropdownMenuItem(value: 'junk', child: Text('ملفات المطوّر والتوثيق فقط')),
            DropdownMenuItem(value: 'off', child: Text('بدون حذف')),
          ],
          onChanged: (v) => setState(() => prune = v ?? prune),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          value: autoPublish,
          onChanged: (v) => setState(() => autoPublish = v),
          title: const Text('نشر للاعبين مباشرة إن نجح كل شيء'),
          subtitle: const Text('إن أُغلق: تذهب اللعبة إلى "للمراجعة"'),
        ),
        SwitchListTile(
          value: media,
          onChanged: (v) => setState(() => media = v),
          title: const Text('تحسين الوسائط'),
          subtitle: const Text('صور→WebP، صوت→Opus، خطوط→WOFF2، فيديو أخف. مع اختبار وتراجع تلقائي'),
        ),
        SwitchListTile(
          value: aiTest,
          onChanged: (v) => setState(() => aiTest = v),
          title: const Text('اختبار بالذكاء الاصطناعي'),
          subtitle: const Text('يلزم حفظ المفتاح وإرساله لأسرار GitHub من الإعدادات'),
        ),
        if (aiTest) field(aiSteps, 'عدد الخطوات (3-60)'),
        field(tags, 'التصنيفات (اختياري)'),
        field(titleAr, 'الاسم بالعربية (اختياري)'),
        ExpansionTile(
          title: const Text('خيارات متقدمة'),
          children: [
            const SizedBox(height: 6),
            field(subdir, 'مجلد الويب داخل المستودع (اختياري)'),
            field(buildCmd, 'أمر بناء مخصص (اختياري)'),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _startImport,
          icon: const Icon(Icons.rocket_launch),
          label: const Padding(padding: EdgeInsets.all(12), child: Text('ابدأ الاستيراد')),
        ),
        const SizedBox(height: 30),
      ]),
    );
  }

  Widget _section(String t, IconData i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Icon(i, color: Pal.lime),
          const SizedBox(width: 8),
          Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.lime)),
        ]),
      );

  // ───────────── تبويب السجل ─────────────
  /// 0 = مرفوضة، 1 = تحذيرات، 2 = نجحت، 3 = ملغاة (قسم سفلي)، -1 = قيد التشغيل/لم تُقرأ نتيجتها بعد
  int _group(Map<String, dynamic> r) {
    final id = r['id'] as int;
    final v = _verdicts[id] ?? ImportVerdicts.cached(id);
    if (v == null || v.level == VLevel.running) return -1;
    switch (v.level) {
      case VLevel.cancelled:
        return 3;
      case VLevel.red:
        return 0;
      case VLevel.orange:
        return 1;
      case VLevel.green:
        return 2;
      case VLevel.running:
        return -1;
    }
  }

  Widget _logTab() {
    if (_loadingRuns) return const Center(child: CircularProgressIndicator());
    if (_runsErr != null) {
      return ListView(padding: const EdgeInsets.all(20), children: [Text(_runsErr!, style: const TextStyle(color: Pal.bad))]);
    }
    final pending = [for (final r in _runs) if (_group(r) == -1) r];
    final cancelled = [for (final r in _runs) if (_group(r) == 3) r];
    final groups = [
      for (var g = 0; g < 3; g++) [for (final r in _runs) if (_group(r) == g) r]
    ];
    return Column(children: [
      TabBar(
        controller: _logTabs,
        indicatorColor: Pal.lime,
        labelColor: Pal.lime,
        unselectedLabelColor: Colors.white54,
        tabs: [
          Tab(text: 'المرفوضة (${groups[0].length})'),
          Tab(text: 'تحذيرات (${groups[1].length})'),
          Tab(text: 'نجحت (${groups[2].length})'),
        ],
      ),
      Expanded(
        child: TabBarView(controller: _logTabs, children: [
          _runList(groups[0], pending, 'لا توجد مرفوضة بين التشغيلات المحمّلة', cancelled),
          _runList(groups[1], pending, 'لا توجد تحذيرات بين التشغيلات المحمّلة', cancelled),
          _runList(groups[2], pending, 'لا توجد ناجحة بلا تحذيرات بين التشغيلات المحمّلة', cancelled),
        ]),
      ),
    ]);
  }

  Widget _runList(List<Map<String, dynamic>> items, List<Map<String, dynamic>> pending, String emptyText,
      List<Map<String, dynamic>> cancelled) {
    return RefreshIndicator(
      onRefresh: () => _loadRuns(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (pending.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
              child: Text('قيد التشغيل أو قراءة النتيجة (${pending.length})',
                  style: const TextStyle(color: Pal.purple, fontWeight: FontWeight.bold)),
            ),
            for (final r in pending) _runCard(r),
            const Divider(height: 24),
          ],
          if (items.isEmpty)
            Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(emptyText, style: const TextStyle(color: Colors.white54))))
          else
            for (final r in items) _runCard(r),
          if (cancelled.isNotEmpty) ...[
            const Divider(height: 24),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const PageStorageKey('cancelled_runs'),
                leading: const Icon(Icons.cancel, color: Colors.grey),
                title: Text('الملغاة (${cancelled.length})', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                children: [for (final r in cancelled) _runCard(r)],
              ),
            ),
          ],
          if (_runs.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا توجد تشغيلات')))
          else if (!_more)
            const Padding(
                padding: EdgeInsets.all(16), child: Center(child: Text('هذه كل التشغيلات', style: TextStyle(color: Colors.white38))))
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: _loadingMore ? null : _loadMore,
                icon: _loadingMore
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.expand_more),
                label: const Text('عرض تشغيلات أقدم'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _runCard(Map<String, dynamic> r) {
    final id = r['id'] as int;
    final v = _verdicts[id] ?? ImportVerdicts.cached(id);
    final st = '${r['status']}';
    final running = st != 'completed';
    Widget icon;
    Color color;
    String head;
    String detail = '';
    if (v == null) {
      // لم يُقرأ الحكم بعد: حالة أساسية مؤقتة
      color = running ? Pal.purple : Colors.grey;
      icon = const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5));
      head = running ? (st == 'queued' ? 'في الانتظار' : 'يعمل') : 'جارٍ قراءة النتيجة...';
    } else {
      color = v.color;
      icon = v.level == VLevel.running
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
          : Icon(v.icon, color: color);
      head = v.label;
      switch (v.level) {
        case VLevel.red:
          detail = v.title;
          break;
        case VLevel.orange:
          detail = '${v.warnings.length} ملاحظة تحتاج نظرة';
          break;
        case VLevel.green:
          detail = 'في «للمراجعة»، لم تُرصد مشاكل';
          break;
        default:
          break;
      }
    }
    final name = (v != null && v.repoName.isNotEmpty) ? v.repoName : '${r['name']} #${r['run_number']}';
    return Card(
      color: Pal.surface,
      shape: Pal.cardShape(color),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: icon,
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text.rich(TextSpan(children: [
          TextSpan(text: head, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          TextSpan(text: ' · ${_ago(r['created_at'])}'),
          if (detail.isNotEmpty) TextSpan(text: '\n$detail'),
        ]), maxLines: 3, overflow: TextOverflow.ellipsis),
        isThreeLine: detail.isNotEmpty,
        trailing: const Icon(Icons.chevron_left),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => RunDetailScreen(run: r)));
          _loadRuns(silent: true);
        },
      ),
    );
  }
}

String _ago(dynamic iso) {
  final t = DateTime.tryParse('$iso')?.toLocal();
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'الآن';
  if (d.inMinutes < 60) return 'قبل ${d.inMinutes} د';
  if (d.inHours < 24) return 'قبل ${d.inHours} س';
  return 'قبل ${d.inDays} يوم';
}

String _size(dynamic b) {
  final n = (b is num) ? b.toDouble() : 0.0;
  if (n >= 1048576) return '${(n / 1048576).toStringAsFixed(1)} MB';
  return '${(n / 1024).toStringAsFixed(0)} KB';
}

// ───────────── تفاصيل تشغيل ─────────────
class RunDetailScreen extends StatefulWidget {
  final Map<String, dynamic> run;
  const RunDetailScreen({super.key, required this.run});
  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  late Map<String, dynamic> run = widget.run;
  List<Map<String, dynamic>> jobs = [];
  final Map<int, List<Map<String, String>>> errors = {};
  List<Map<String, dynamic>> arts = [];
  Verdict? verdict;
  bool loading = true;
  String? err;
  Timer? _timer;

  int get id => run['id'] as int;
  bool get running => run['status'] != 'completed';

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (running) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => loading = true);
    try {
      run = await ActionsApi.run(id);
      jobs = await ActionsApi.jobs(id);
      for (final j in jobs) {
        if (j['status'] == 'completed' && !errors.containsKey(j['id'])) {
          try {
            errors[j['id'] as int] = await ActionsApi.annotations(j['id'] as int);
          } catch (_) {
            errors[j['id'] as int] = [];
          }
        }
      }
      try {
        verdict = await ImportVerdicts.resolve(run, force: true);
      } catch (_) {}
      if (!running) arts = await ActionsApi.artifacts(id);
      err = null;
    } catch (e) {
      err = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _act(Future<void> Function() f, String ok) async {
    try {
      await f();
      if (mounted) toast(context, ok);
      await Future.delayed(const Duration(seconds: 2));
      _load(silent: true);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  IconData _icon(dynamic status, dynamic concl) {
    if (status != 'completed') return Icons.autorenew;
    switch ('$concl') {
      case 'success':
        return Icons.check_circle;
      case 'skipped':
        return Icons.remove_circle_outline;
      case 'cancelled':
        return Icons.cancel;
    }
    return Icons.error;
  }

  Color _color(dynamic status, dynamic concl) {
    if (status != 'completed') return Pal.purple;
    switch ('$concl') {
      case 'success':
        return Pal.ok;
      case 'skipped':
      case 'cancelled':
        return Colors.grey;
    }
    return Pal.bad;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${run['name']} #${run['run_number']}'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(14), children: [
              if (err != null) Text(err!, style: const TextStyle(color: Pal.bad)),
              if (verdict != null) _verdictPanel(verdict!),
              Text(_ago(run['created_at']), style: const TextStyle(color: Colors.white60)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 6, children: [
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse('${run['html_url']}'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('فتح في GitHub'),
                ),
                if (running)
                  OutlinedButton.icon(
                      onPressed: () => _act(() => ActionsApi.cancel(id), 'طُلب الإلغاء'),
                      icon: const Icon(Icons.stop_circle),
                      label: const Text('إلغاء'))
                else ...[
                  if (run['conclusion'] == 'failure')
                    OutlinedButton.icon(
                        onPressed: () => _act(() => ActionsApi.rerunFailed(id), 'أُعيد تشغيل الفاشل'),
                        icon: const Icon(Icons.replay),
                        label: const Text('إعادة الفاشل')),
                  OutlinedButton.icon(
                      onPressed: () => _act(() => ActionsApi.rerun(id), 'أُعيد التشغيل'),
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('إعادة الكل')),
                ],
              ]),
              const SizedBox(height: 16),
              if (arts.isNotEmpty) ...[
                const Text('الملفات الناتجة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.lime)),
                for (final a in arts)
                  Card(
                    color: Pal.surface,
                    shape: Pal.cardShape(Pal.ok),
                    child: ListTile(
                      leading: const Icon(Icons.android, color: Pal.ok),
                      title: Text('${a['name']}'),
                      subtitle: Text(a['expired'] == true ? 'منتهية الصلاحية' : 'الحجم المضغوط: ${_size(a['size_in_bytes'])}'),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('للتحميل: اضغط «فتح في GitHub» ثم Artifacts أسفل الصفحة.',
                      style: TextStyle(fontSize: 12, color: Colors.white60)),
                ),
                const SizedBox(height: 10),
              ],
              const Text('المراحل', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.lime)),
              for (final j in jobs) _job(j),
            ]),
    );
  }

  Widget _verdictPanel(Verdict v) {
    final c = v.color;
    Widget block(String head, String body) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(head, style: TextStyle(fontWeight: FontWeight.bold, color: c)),
            const SizedBox(height: 3),
            SelectableText(body, style: const TextStyle(fontSize: 14, height: 1.5)),
          ]),
        );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withOpacity(0.13),
        border: Border.all(color: c.withOpacity(0.7), width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          v.level == VLevel.running
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Icon(v.icon, color: c),
          const SizedBox(width: 8),
          Expanded(
              child: Text('${v.label}: ${v.title}',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: c))),
        ]),
        if (v.repoName.isNotEmpty) block('المستودع', 'https://github.com/${v.repoName}'),
        if (v.stage.isNotEmpty && v.level == VLevel.running) block('المرحلة الآن', v.stage),
        if (v.why.isNotEmpty) block('ماذا حدث', v.why),
        if (v.advice.isNotEmpty) block('ما العمل', v.advice),
        if (v.reasons.isNotEmpty) block('تفاصيل الرفض', v.reasons.map((e) => '• $e').join('\n')),
        if (v.warnings.isNotEmpty) block('التحذيرات', v.warnings.map((e) => '• $e').join('\n')),
      ]),
    );
  }

  Widget _note(Map<String, String> a) {
    final lvl = a['level'];
    final color = lvl == 'failure' ? Pal.bad : (lvl == 'warning' ? Pal.warn : Pal.ok);
    final title = a['title'] ?? '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty)
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        if (title.isNotEmpty) const SizedBox(height: 4),
        SelectableText(a['message'] ?? '', style: const TextStyle(fontSize: 12.5, height: 1.45)),
      ]),
    );
  }

  Widget _job(Map<String, dynamic> j) {
    final steps = (j['steps'] is List) ? List<Map<String, dynamic>>.from((j['steps'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e))) : <Map<String, dynamic>>[];
    final c = _color(j['status'], j['conclusion']);
    final errs = errors[j['id']] ?? [];
    return Card(
      color: Pal.surface,
      shape: Pal.cardShape(c),
      margin: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(_icon(j['status'], j['conclusion']), color: c),
        title: Text('${j['name']}'),
        children: [
          for (final s in steps)
            ListTile(
              dense: true,
              leading: Icon(_icon(s['status'], s['conclusion']), size: 18, color: _color(s['status'], s['conclusion'])),
              title: Text('${s['name']}'),
            ),
          for (final a in errs)
            if ((a['title'] ?? '') != 'خيال-نتيجة') _note(a),
        ],
      ),
    );
  }
}
