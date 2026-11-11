import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'consts.dart';
import 'github.dart';
import 'theme.dart';
import 'ui.dart';
import 'game_form_screen.dart';
import 'queue_api.dart';
import 'seen_games.dart';

/// قائمة ألعاب واحدة (المنشورة، المميزة، أو للمراجعة) بحث وفلتر ومحتوى كل بطاقة.
/// البيانات تأتي من الشاشة الأم (`games/featured/pending`)، و`onReload` يعيد تحميلها بعد أي تغيير.
class GamesPane extends StatefulWidget {
  final int tab; // 0 المنشورة، 1 المميزة، 2 للمراجعة
  final List<Map<String, dynamic>> games;
  final List<Map<String, dynamic>> featured;
  final List<Map<String, dynamic>> pending;
  final bool loading;
  final Future<void> Function() onReload;
  final VoidCallback? onSeenChanged;
  const GamesPane({
    super.key,
    required this.tab,
    required this.games,
    required this.featured,
    required this.pending,
    required this.loading,
    required this.onReload,
    this.onSeenChanged,
  });
  @override
  State<GamesPane> createState() => _GamesPaneState();
}

class _GamesPaneState extends State<GamesPane> with AutomaticKeepAliveClientMixin {
  String _q = '';
  String _filter = 'all';

  @override
  bool get wantKeepAlive => true;

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
    await widget.onReload();
  }

  List<Map<String, dynamic>> get _source =>
      widget.tab == 0 ? widget.games : (widget.tab == 1 ? widget.featured : widget.pending);

  List<Map<String, dynamic>> get _shown {
    return _source.where((g) {
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
        case 'unseen':
          return SeenGames.badge(g) != null;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final list = _shown;
    final unseen = _source.where((g) => SeenGames.badge(g) != null).toList();
    return Column(children: [
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
              DropdownMenuItem(value: 'unseen', child: Text('لم تُفتح')),
              DropdownMenuItem(value: 'top', child: Text('★8+')),
              DropdownMenuItem(value: 'new', child: Text('2020+')),
              DropdownMenuItem(value: 'bad', child: Text('غير صالحة')),
            ],
            onChanged: (v) => setState(() => _filter = v ?? 'all'),
          ),
        ]),
      ),
      if (unseen.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 8, 0),
          child: Row(children: [
            const Icon(Icons.fiber_new, color: Pal.lime, size: 20),
            const SizedBox(width: 6),
            Expanded(child: Text('${unseen.length} لم تُفتح بعد (جديدة أو معادة الاستيراد)', style: const TextStyle(fontSize: 12.5, color: Colors.white70))),
            TextButton(
              onPressed: () async {
                await SeenGames.markAll(unseen);
                widget.onSeenChanged?.call();
                if (mounted) setState(() {});
              },
              child: const Text('تعليم الكل كمفتوحة'),
            ),
          ]),
        ),
      Expanded(
        child: widget.loading && _source.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: widget.onReload,
                child: list.isEmpty
                    ? ListView(children: const [SizedBox(height: 120), Center(child: Text('لا توجد ألعاب'))])
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) => _card(list[i]),
                      ),
              ),
      ),
    ]);
  }

  /// يعيد "طبخ" اللعبة بأحدث نسخة من أدوات المعالجة: يجلب المستودع الأصلي من جديد ويُشغّل import-game.yml.
  /// publish.py يتعرّف على اللعبة من source_url فيحدّث ملفاتها فقط دون المساس بسجلها (الاسم، التقييم، التصنيفات...).
  /// ملاحظات الاستيراد المحفوظة مع ملفات اللعبة (games/<slug>/_import_report.json)
  Future<void> _showNotes(Map<String, dynamic> g) async {
    final d = (g['details_scene'] as Map?) ?? {};
    final play = '${d['play_url'] ?? ''}';
    if (!play.startsWith('https://')) {
      toast(context, 'لا رابط لعب لهذه اللعبة', error: true);
      return;
    }
    Map<String, dynamic>? rep;
    String? err;
    try {
      final base = play.endsWith('/') ? play : '$play/';
      final r = await http
          .get(Uri.parse('${base}_import_report.json?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) {
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        if (j is Map<String, dynamic>) rep = j;
      } else if (r.statusCode == 404) {
        err = 'لا ملاحظات محفوظة لهذه اللعبة (استُوردت قبل هذه الميزة). أعد استيرادها لتُحفظ.';
      } else {
        err = 'تعذّر الجلب (${r.statusCode})';
      }
    } catch (e) {
      err = 'تعذّر الجلب: $e';
    }
    if (!mounted) return;
    List<String> lst(String k) => [for (final x in (rep?[k] as List? ?? const [])) '$x'];
    Widget sec(String title, List<String> items, Color c) => items.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$title (${items.length})', style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 4),
              for (final x in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: SelectableText('• $x', style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.5)),
                ),
            ]),
          );
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.surface,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (_, ctl) => ListView(
          controller: ctl,
          padding: const EdgeInsets.all(18),
          children: [
            Text('ملاحظات استيراد: ${(g['main_scene'] as Map?)?['title_ar'] ?? ''}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            if (rep != null) Text('${rep['date'] ?? ''} · الحالة: ${rep['status'] ?? ''}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 12),
            if (err != null) Text(err, style: const TextStyle(color: Pal.warn)),
            if (rep != null) ...[
              sec('تحذيرات', lst('warnings'), Pal.warn),
              sec('ملاحظات', lst('notes'), Pal.ok),
              sec('أخطاء الكونسول', lst('console_errors'), Pal.bad),
              sec('ملفات لم تُحمَّل', lst('failed_requests'), Pal.bad),
              sec('طلبات خارجية', lst('external_requests'), Pal.purple),
              sec('مرشّحو الغلاف', lst('cover_candidates'), Pal.purple),
            ],
          ],
        ),
      ),
    );
  }

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
    // لا نرسل مباشرة إلى import-game: GitHub يُلغي التشغيلات المنتظرة المتتالية. نجمعها في طابور واحد.
    QueueApi.addReimport(url, (o == 'portrait' || o == 'landscape' || o == 'both') ? o : 'portrait', (m, err) {
      if (mounted) toast(context, m, error: err);
    });
  }

  Widget _card(Map<String, dynamic> g) {
    final main = _m(g['main_scene']);
    final d = _m(g['details_scene']);
    final poster = '${main['poster_url'] ?? ''}';
    final why = validateGame(g);
    final badge = SeenGames.badge(g);
    return Card(
      color: Pal.surface,
      shape: Pal.cardShape(why.isNotEmpty ? Pal.warn : (badge != null ? Pal.lime : null)),
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
        title: Row(children: [
          Flexible(child: Text('${main['title_ar'] ?? '?'}')),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: (g['reimported_at'] != null ? Colors.orangeAccent : Pal.lime).withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(badge,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: g['reimported_at'] != null ? Colors.orangeAccent : Pal.lime)),
            ),
          ],
        ]),
        subtitle: Text(
          '#${g['id']} · ★ ${main['app_rating'] ?? 0} · ${g['release_year'] ?? ''} · ${d['license'] ?? '-'}'
          '${why.isEmpty ? '' : '\n⚠️ $why'}',
          style: TextStyle(color: why.isEmpty ? null : Pal.warn),
        ),
        isThreeLine: why.isNotEmpty,
        trailing: widget.tab == 2
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'ملاحظات الاستيراد',
                  icon: const Icon(Icons.fact_check_outlined, color: Pal.warn),
                  onPressed: () => _showNotes(g),
                ),
                IconButton(
                  tooltip: 'إعادة الاستيراد من المصدر',
                  icon: const Icon(Icons.refresh, color: Pal.lime),
                  onPressed: () => _reimport(g),
                ),
              ])
            : PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'hide') _hide(g);
                  if (v == 'reimport') _reimport(g);
                  if (v == 'notes') _showNotes(g);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'notes', child: Text('ملاحظات الاستيراد')),
                  PopupMenuItem(value: 'reimport', child: Text('إعادة الاستيراد من المصدر')),
                  PopupMenuItem(value: 'hide', child: Text('إخفاء حتى المراجعة')),
                ],
              ),
        onTap: () async {
          await SeenGames.markSeen(g);
          widget.onSeenChanged?.call();
          if (mounted) setState(() {});
          if (!mounted) return;
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => GameFormScreen(
                        item: g,
                        isFeatured: widget.featured.any((f) => '${f['id']}' == '${g['id']}'),
                        fromPending: widget.tab == 2,
                      )));
          widget.onReload();
        },
      ),
    );
  }
}
