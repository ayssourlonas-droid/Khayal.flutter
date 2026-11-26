import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'consts.dart';
import 'github.dart';
import 'license_info.dart';
import 'theme.dart';
import 'ui.dart';

/// مشهد التراخيص: يفحص رخصة كل لعبة (منشورة ومميزة وللمراجعة) ويصنّفها حرة / متوسطة / ممنوعة / بعقد،
/// ويعرض تفاصيل الرخصة وواجباتها، وللألعاب بعقد بيانات العقد. ملخص للمراجعة وليس استشارة قانونية.
class LicensesScreen extends StatefulWidget {
  const LicensesScreen({super.key});
  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _Row {
  final Map<String, dynamic> game;
  final String group; // منشورة | مميزة | للمراجعة
  final String title;
  final String slug;
  final String spdx;
  final LicInfo info;
  final bool contractMissing;
  _Row(this.game, this.group, this.title, this.slug, this.spdx, this.info, this.contractMissing);
}

class _LicensesScreenState extends State<LicensesScreen> {
  List<_Row> _rows = [];
  Map<String, Map<String, dynamic>> _index = {};
  bool _loading = true;
  String _q = '';
  LicClass? _filter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static Map _m(dynamic v) => v is Map ? v : {};

  static String _slugOf(Map<String, dynamic> g) {
    final u = (_m(g['details_scene'])['play_url'] ?? '').toString();
    final m = RegExp(r'/games/([^/]+)/?').firstMatch(u);
    return m?.group(1) ?? '';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = <_Row>[];
      void add(List<Map<String, dynamic>> src, String group) {
        for (final g in src) {
          final d = _m(g['details_scene']);
          final spdx = (d['license'] ?? '').toString();
          final info = LicInfo.of(spdx);
          final hasContract = (g['contract'] ?? d['contract']) is Map && ((g['contract'] ?? d['contract']) as Map).isNotEmpty;
          rows.add(_Row(g, group, (_m(g['main_scene'])['title_ar'] ?? _m(g['main_scene'])['title_en'] ?? '?').toString(),
              _slugOf(g), spdx, info, info.cls == LicClass.contract && !hasContract));
        }
      }

      add(Github.asList((await Github.getJson(gamesFile)).data), 'منشورة');
      add(Github.asList((await Github.getJson(featuredFile)).data), 'مميزة');
      add(Github.asList((await Github.getJson(pendingFile)).data), 'للمراجعة');
      final idx = <String, Map<String, dynamic>>{};
      try {
        for (final e in Github.asList((await Github.getJson('data_import_index.json')).data)) {
          idx[(e['slug'] ?? '').toString()] = e;
        }
      } catch (_) {}
      const order = {LicClass.banned: 0, LicClass.contract: 1, LicClass.medium: 2, LicClass.free: 3};
      rows.sort((a, b) {
        final c = order[a.info.cls]!.compareTo(order[b.info.cls]!);
        return c != 0 ? c : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
      _rows = rows;
      _index = idx;
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  int _count(LicClass c) => _rows.where((r) => r.info.cls == c).length;

  Widget _chip(String label, int n, Color c, LicClass? cls) {
    final sel = _filter == cls;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _filter = sel ? null : cls),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: c.withOpacity(sel ? 0.32 : 0.12),
            border: Border.all(color: sel ? c : c.withOpacity(0.5), width: sel ? 2 : 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Text(_loading ? '…' : '$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c)),
            Text(label, style: const TextStyle(fontSize: 12.5)),
          ]),
        ),
      ),
    );
  }

  Widget _badge(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: c.withOpacity(0.2), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withOpacity(0.6))),
        child: Text(text, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
      );

  List<_Row> get _shown {
    final q = _q.trim().toLowerCase();
    return _rows.where((r) {
      if (_filter != null && r.info.cls != _filter) return false;
      if (q.isEmpty) return true;
      return '${r.title} ${r.spdx} ${r.slug} ${_m(r.game['details_scene'])['developer'] ?? ''}'.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final banned = _count(LicClass.banned);
    final noContract = _rows.where((r) => r.contractMissing).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('التراخيص'),
        actions: [IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 24), children: [
          Row(children: [
            _chip('حرة', _count(LicClass.free), LicInfo.clsColor(LicClass.free), LicClass.free),
            const SizedBox(width: 6),
            _chip('متوسطة', _count(LicClass.medium), LicInfo.clsColor(LicClass.medium), LicClass.medium),
            const SizedBox(width: 6),
            _chip('ممنوعة', banned, LicInfo.clsColor(LicClass.banned), LicClass.banned),
            const SizedBox(width: 6),
            _chip('بعقد', _count(LicClass.contract), LicInfo.clsColor(LicClass.contract), LicClass.contract),
          ]),
          if (!_loading && (banned > 0 || noContract > 0)) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Pal.bad.withOpacity(0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.bad.withOpacity(0.6))),
              child: Text(
                [
                  if (banned > 0) '⛔ $banned لعبة برخصة ممنوعة أو غير معروفة: أخفِها أو احذفها قبل أي كسب.',
                  if (noContract > 0) '📄 $noContract لعبة بعقد بلا بيانات عقد مسجّلة.',
                ].join('\n'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث بالاسم أو الرخصة أو المطوّر'),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
          else if (shown.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا توجد ألعاب مطابقة')))
          else
            for (final r in shown)
              Card(
                color: Pal.surface,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${r.group} · ${_m(r.game['details_scene'])['developer'] ?? ''}${r.contractMissing ? ' · العقد غير مسجّل' : ''}',
                      style: const TextStyle(fontSize: 12.5)),
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    _badge(LicInfo.clsLabel(r.info.cls), LicInfo.clsColor(r.info.cls)),
                    const SizedBox(height: 3),
                    Text(r.spdx.isEmpty ? '—' : r.spdx, style: const TextStyle(fontSize: 11.5, color: Colors.white60)),
                  ]),
                  onTap: () => _open(r),
                ),
              ),
        ]),
      ),
    );
  }

  /// ملفات اللعبة (تقرير الاستيراد ونص الرخصة) تُقرأ من موقعها المنشور لا من مستودع GitHub المضبوط في الإعدادات،
  /// لأن البيانات والاستضافة قد تكونان في مستودعين مختلفين (khayal.data / khayal-control).
  Future<String?> _fetch(String playUrl, String file) async {
    final base = Uri.tryParse(playUrl);
    if (base == null || base.scheme != 'https' || file.isEmpty) return null;
    try {
      final r = await http.get(base.resolve(file)).timeout(const Duration(seconds: 12));
      return r.statusCode == 200 ? utf8.decode(r.bodyBytes) : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _report(String playUrl) async {
    final t = await _fetch(playUrl, '_import_report.json');
    if (t == null) return null;
    try {
      final d = jsonDecode(t);
      return d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _licenseText(String playUrl, String file) async {
    final t = await _fetch(playUrl, file);
    if (t == null) return null;
    return t.length > 700 ? '${t.substring(0, 700)}…' : t;
  }

  Widget _section(String title, Widget child, {Color? color}) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color ?? Pal.lime)),
          const SizedBox(height: 4),
          child,
        ]),
      );

  Widget _bullets(List<String> items, {String mark = '•'}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final s in items) Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('$mark $s', style: const TextStyle(fontSize: 13.5)))],
      );

  void _open(_Row r) {
    final d = _m(r.game['details_scene']);
    final idx = _index[r.slug];
    final c = LicInfo.clsColor(r.info.cls);
    final contract = ((r.game['contract'] ?? d['contract']) is Map) ? Map<String, dynamic>.from((r.game['contract'] ?? d['contract']) as Map) : <String, dynamic>{};
    final src = (d['source_url'] ?? '').toString();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(18, 16, 18, 30), children: [
          Row(children: [
            Expanded(child: Text(r.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
            _badge(LicInfo.clsLabel(r.info.cls), c),
          ]),
          const SizedBox(height: 4),
          Text('${r.info.name}${r.spdx.isNotEmpty && r.spdx != r.info.name ? ' (${r.spdx})' : ''} · ${r.group} · ${d['developer'] ?? ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          _section('ماذا تعني', Text(r.info.summary, style: const TextStyle(fontSize: 13.5)), color: c),
          if (r.info.can.isNotEmpty) _section('المسموح', _bullets(r.info.can, mark: '✓'), color: Pal.ok),
          if (r.info.must.isNotEmpty) _section('واجباتك', _bullets(r.info.must, mark: '▸'), color: Pal.warn),
          if (r.info.watch.isNotEmpty) _section('انتبه', _bullets(r.info.watch, mark: '⚠'), color: Pal.bad),
          if (r.info.cls == LicClass.contract)
            _section(
              'بيانات العقد',
              contract.isEmpty
                  ? const Text(
                      'لا بيانات عقد مسجّلة لهذه اللعبة.\nأضف حقل contract في سجلها (data_games*.json) بالمفاتيح: party (الطرف)، date (التاريخ)، '
                      'expires (الانتهاء)، scope (النطاق: إعلانات/اشتراكات/ترجمة)، revenue_share (الحصة)، evidence_url (رابط الدليل)، notes.',
                      style: TextStyle(fontSize: 13.5, height: 1.5))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final e in const {
                        'party': 'الطرف الآخر',
                        'date': 'تاريخ العقد',
                        'expires': 'ينتهي في',
                        'scope': 'النطاق',
                        'revenue_share': 'حصة الأرباح',
                        'evidence_url': 'رابط الدليل',
                        'notes': 'ملاحظات',
                      }.entries)
                        if ((contract[e.key] ?? '').toString().trim().isNotEmpty)
                          Padding(padding: const EdgeInsets.only(bottom: 3), child: SelectableText('${e.value}: ${contract[e.key]}', style: const TextStyle(fontSize: 13.5))),
                    ]),
              color: Pal.info,
            ),
          _section(
            'المصدر والدليل',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (src.isNotEmpty) SelectableText(src, style: const TextStyle(fontSize: 13, color: Colors.white70)),
              if (idx != null)
                Text('ملف الرخصة: ${idx['license_file'] ?? '—'} · الإصدار: ${(idx['commit'] ?? '').toString().length >= 7 ? (idx['commit'] as String).substring(0, 7) : '—'} · ${idx['date'] ?? ''}',
                    style: const TextStyle(fontSize: 12.5, color: Colors.white60)),
              if (src.startsWith('http'))
                TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse(src), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('فتح المصدر')),
            ]),
          ),
          FutureBuilder<List<dynamic>>(
            future: Future.wait([_report((d['play_url'] ?? '').toString()), _licenseText((d['play_url'] ?? '').toString(), (idx?['license_file'] ?? 'LICENSE').toString())]),
            builder: (_, snap) {
              if (!snap.hasData) return const Padding(padding: EdgeInsets.only(top: 16), child: Center(child: CircularProgressIndicator()));
              final rep = snap.data![0] as Map<String, dynamic>?;
              final lic = snap.data![1] as String?;
              final prov = rep?['provenance'];
              final summary = prov is Map ? (prov['summary_ar'] ?? '').toString() : '';
              final warns = rep?['warnings'] is List ? (rep!['warnings'] as List).map((e) => e.toString()).toList() : <String>[];
              final licWarns = warns.where((w) => RegExp(r'رخص|مصدر|حقوق|وسائط|صور|أصوات|خط').hasMatch(w)).take(6).toList();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _section(
                  'الصور والأصوات والخطوط',
                  summary.isNotEmpty || licWarns.isNotEmpty
                      ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (summary.isNotEmpty) Text(summary, style: const TextStyle(fontSize: 13.5)),
                          if (licWarns.isNotEmpty) _bullets(licWarns, mark: '⚠'),
                        ])
                      : Text(rep == null ? 'لا تقرير استيراد لهذه اللعبة.' : 'لم يُسجَّل تحذير عن الوسائط (إشارات آلية وليست ضماناً).',
                          style: const TextStyle(fontSize: 13.5)),
                  color: Pal.teal,
                ),
                if (lic != null)
                  _section('مقتطف من ملف الرخصة', SelectableText(lic, style: const TextStyle(fontSize: 11.5, color: Colors.white60, height: 1.4)),
                      color: Colors.white70),
              ]);
            },
          ),
          const SizedBox(height: 18),
          const Text('ملخص عملي للمراجعة وليس استشارة قانونية. راجع مختصاً قبل الكسب.', style: TextStyle(fontSize: 11.5, color: Colors.white38)),
        ]),
      ),
    );
  }
}
