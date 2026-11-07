import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'actions_api.dart';
import 'discover_api.dart';
import 'name_key.dart';
import 'theme.dart';
import 'ui.dart';

/// اكتشاف ألعاب ويب على GitHub برخص مسموحة، ثم استيراد المحدد منها واحدة بعد أخرى.
/// الطابور يعمل على خادم GitHub (workflow باسم import-queue.yml)، فلا يتوقف إن أُغلق التطبيق.
class DiscoverTab extends StatefulWidget {
  final VoidCallback onStarted;
  const DiscoverTab({super.key, required this.onStarted});
  @override
  State<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<DiscoverTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const _wf = 'import-queue.yml';
  static const topics = ['html5-game', 'web-game', 'javascript-game', 'phaser', 'canvas-game', 'puzzle-game'];

  final nameCtl = TextEditingController();
  String topic = topics.first;
  int minStars = 20;
  bool recentOnly = true;
  String? lic; // null = كل المسموحة
  bool media = true;
  bool aiTest = false;
  String orientation = 'portrait';

  bool _searching = false;
  String? _err;
  List<FoundRepo> _results = [];
  Set<String> _known = {};
  List<SeenEntry> _seen = [];
  // مفتاح المستودع -> ملاحظة (مكررة/اسم مشابه) ؛ والمخفي من النسخ المشابهة داخل النتائج
  final Map<String, String> _note = {};
  final Map<String, int> _hiddenCount = {};
  final Set<String> _hidden = {};
  final Set<String> _selected = {};

  // الطابور
  bool _running = false;
  final Map<String, String> _state = {}; // fullName -> نص الحالة
  final List<String> _order = [];

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _err = null;
    });
    try {
      final known = await DiscoverApi.knownSources();
      final seen = await DiscoverApi.seenEntries();
      final res = await DiscoverApi.search(
          name: nameCtl.text, topic: topic, minStars: minStars, recentOnly: recentOnly, onlyLicense: lic);
      _note.clear();
      _hidden.clear();
      _hiddenCount.clear();
      // 1) مقارنة بالسجل السابق: اسم + حجم متقارب = مكررة محتملة (تُخفى)، اسم فقط = تنبيه
      final primaries = <String, FoundRepo>{};
      final shown = <FoundRepo>[];
      for (final r in res) {
        final k = r.key;
        final prev = seen.where((e) => e.key == k).toList();
        if (prev.any((e) => similarSize(e.sizeKb, r.sizeKb))) {
          _hidden.add(r.fullName);
          continue;
        }
        if (prev.isNotEmpty) _note[r.fullName] = 'اسم مشابه لـ ${prev.first.label} (حجم مختلف)';
        // 2) داخل النتائج نفسها: نفس المفتاح والحجم المتقارب = نسخة مشابهة، نخفيها تحت الأعلى نجوماً
        final p = primaries[k];
        if (p != null && similarSize(p.sizeKb, r.sizeKb)) {
          _hidden.add(r.fullName);
          _hiddenCount[p.fullName] = (_hiddenCount[p.fullName] ?? 0) + 1;
          continue;
        }
        if (p != null) {
          _note[r.fullName] = 'اسم مشابه لـ ${p.fullName} (حجم مختلف)';
        } else {
          primaries[k] = r;
        }
        shown.add(r);
      }
      if (!mounted) return;
      setState(() {
        _seen = seen;
        _known = known;
        _results = shown;
        _selected.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
    if (mounted) setState(() => _searching = false);
  }

  bool _isKnown(FoundRepo r) => _known.contains(DiscoverApi.norm(r.url));

  /// يرسل القائمة كاملة مرة واحدة إلى طابور GitHub؛ بعدها يمكن إغلاق التطبيق.
  Future<void> _startQueue() async {
    final list = _results.where((r) => _selected.contains(r.fullName) && !_isKnown(r)).toList();
    if (list.isEmpty) return;
    setState(() {
      _running = true;
      _order
        ..clear()
        ..addAll(list.map((e) => e.fullName));
      for (final r in list) {
        _state[r.fullName] = 'يُرسل إلى الطابور...';
      }
    });
    try {
      await ActionsApi.dispatch(_wf, {
        'urls': list.map((e) => e.url).join('\n'),
        'orientation': orientation,
        'prune': 'smart',
        'media': media ? 'safe' : 'off',
        'ai_test': aiTest ? 'yes' : 'no',
      });
      for (final r in list) {
        _state[r.fullName] = 'في طابور GitHub (يكمل حتى لو أُغلق التطبيق)';
      }
      widget.onStarted();
      if (mounted) {
        toast(context, 'أُرسلت ${list.length} لعبة إلى الطابور؛ يمكنك إغلاق التطبيق وتتبّع النتائج في تبويب السجل');
      }
    } catch (e) {
      for (final r in list) {
        _state[r.fullName] = 'تعذّر الإرسال: $e';
      }
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _running = false);
  }

  void _set(String k, String v) {
    if (mounted) setState(() => _state[k] = v);
  }


  @override
  Widget build(BuildContext context) {
    super.build(context);
    final canStart = !_running && _selected.isNotEmpty;
    return ListView(padding: const EdgeInsets.all(14), children: [
      const Text('يبحث في GitHub عن ألعاب برخص مسموحة. الفحص النهائي للرخصة يتم عند الاستيراد، وكل لعبة تذهب إلى «للمراجعة».',
          style: TextStyle(fontSize: 12, color: Colors.white60)),
      const SizedBox(height: 10),
      field(nameCtl, 'اسم اللعبة (اختياري: إن تُرك فارغاً يبحث بالتصنيف)'),
      DropdownButtonFormField<String>(
        value: topic,
        decoration: const InputDecoration(labelText: 'التصنيف (topic) في GitHub'),
        items: [for (final t in topics) DropdownMenuItem(value: t, child: Text(t))],
        onChanged: (v) => setState(() => topic = v ?? topic),
      ),
      DropdownButtonFormField<String?>(
        value: lic,
        decoration: const InputDecoration(labelText: 'الرخصة'),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('كل الرخص المسموحة')),
          for (final k in DiscoverApi.licenseKeys.keys) DropdownMenuItem<String?>(value: k, child: Text(k)),
        ],
        onChanged: (v) => setState(() => lic = v),
      ),
      DropdownButtonFormField<int>(
        value: minStars,
        decoration: const InputDecoration(labelText: 'أقل عدد نجوم'),
        items: [for (final n in [0, 5, 20, 50, 100, 500]) DropdownMenuItem(value: n, child: Text('$n+'))],
        onChanged: (v) => setState(() => minStars = v ?? minStars),
      ),
      SwitchListTile(
        value: recentOnly,
        onChanged: (v) => setState(() => recentOnly = v),
        title: const Text('محدّثة خلال آخر سنتين فقط'),
      ),
      const SizedBox(height: 6),
      FilledButton.icon(
        onPressed: _searching || _running ? null : _search,
        icon: const Icon(Icons.search),
        label: const Padding(padding: EdgeInsets.all(10), child: Text('ابحث')),
      ),
      if (_searching) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
      if (_err != null) Padding(padding: const EdgeInsets.all(8), child: Text(_err!, style: const TextStyle(color: Pal.bad))),
      if (_results.isNotEmpty) ...[
        const Divider(height: 28),
        Text('النتائج (${_results.length}) — أُخفيت ${_hidden.length} نسخة مكررة محتملة', style: const TextStyle(fontWeight: FontWeight.bold)),
        for (final r in _results) _tile(r),
        const Divider(height: 28),
        DropdownButtonFormField<String>(
          value: orientation,
          decoration: const InputDecoration(labelText: 'اتجاه الشاشة للمحدد'),
          items: const [
            DropdownMenuItem(value: 'portrait', child: Text('portrait')),
            DropdownMenuItem(value: 'landscape', child: Text('landscape')),
            DropdownMenuItem(value: 'both', child: Text('both')),
          ],
          onChanged: (v) => setState(() => orientation = v ?? orientation),
        ),
        SwitchListTile(value: media, onChanged: (v) => setState(() => media = v), title: const Text('تحسين الوسائط')),
        SwitchListTile(value: aiTest, onChanged: (v) => setState(() => aiTest = v), title: const Text('اختبار بالذكاء الاصطناعي')),
        FilledButton.icon(
          onPressed: canStart ? _startQueue : null,
          icon: const Icon(Icons.playlist_play),
          label: Padding(padding: const EdgeInsets.all(12), child: Text('استورد المحدد (${_selected.length}) واحدة بعد أخرى')),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('يُرسَل الطابور إلى GitHub فيعمل وحده، ويمكنك إغلاق التطبيق؛ كل لعبة تنتظر انتهاء السابقة.',
              style: TextStyle(fontSize: 12, color: Colors.white60)),
        ),
      ],
    ]);
  }

  Widget _tile(FoundRepo r) {
    final known = _isKnown(r);
    final st = _state[r.fullName];
    return Card(
      shape: Pal.cardShape(),
      child: CheckboxListTile(
        value: _selected.contains(r.fullName),
        onChanged: (known || _running)
            ? null
            : (v) => setState(() => v == true ? _selected.add(r.fullName) : _selected.remove(r.fullName)),
        title: Text('${r.fullName}  ⭐${r.stars}', style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          '${known ? '✓ مسجّلة سابقاً\n' : ''}${_note[r.fullName] == null ? '' : '⚠ ${_note[r.fullName]}\n'}${(_hiddenCount[r.fullName] ?? 0) > 0 ? '+${_hiddenCount[r.fullName]} نسخ مشابهة مخفية\n' : ''}${r.desc.isEmpty ? '' : '${r.desc}\n'}'
          '${r.license} • آخر تحديث ${r.pushed}${r.topics.isEmpty ? '' : '\n${r.topics}'}'
          '${st == null ? '' : '\n» $st'}',
          style: const TextStyle(fontSize: 12),
        ),
        secondary: IconButton(
          icon: const Icon(Icons.open_in_new, size: 20),
          onPressed: () => launchUrl(Uri.parse(r.url), mode: LaunchMode.externalApplication),
        ),
      ),
    );
  }
}
