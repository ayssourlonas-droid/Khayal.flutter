import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'actions_api.dart';
import 'discover_api.dart';
import 'queue_api.dart';
import 'name_key.dart';
import 'rejected_screen.dart';
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
  static const allTopics = '__all__';
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
  Set<String> _rejected = {};
  bool _showRejected = false;
  int _rejHidden = 0;
  int _fetched = -1; // عدد ما جلبه GitHub في آخر بحث (-1 = لم يُجرَ بحث)
  int _knownInFetched = 0;
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
      final rejected = await DiscoverApi.rejectedSources();
      final exclude = <String>{...known, if (!_showRejected) ...rejected};
      // «كل التصنيفات»: نبحث في كل تصنيف على حدة ثم ندمج (البحث بالاسم لا يستعمل التصنيف)
      final all = topic == allTopics && nameCtl.text.trim().isEmpty;
      final tops = all ? topics : [topic];
      final merged = <String, FoundRepo>{};
      String? warn;
      for (final t in tops) {
        try {
          final part = await DiscoverApi.search(
              name: nameCtl.text,
              topic: t,
              minStars: minStars,
              recentOnly: recentOnly,
              onlyLicense: lic,
              exclude: exclude,
              wantNew: all ? 15 : 30,
              maxPages: all ? 3 : 8);
          for (final r in part) {
            merged[r.fullName] = r;
          }
          if (DiscoverApi.lastWarning != null) warn = DiscoverApi.lastWarning;
        } catch (e) {
          if (merged.isEmpty) rethrow;
          warn = 'توقف البحث مبكراً: $e';
          break;
        }
      }
      DiscoverApi.lastWarning = warn;
      final res = merged.values.toList()..sort((a, b) => b.stars.compareTo(a.stars));
      _note.clear();
      _hidden.clear();
      _hiddenCount.clear();
      // 1) مقارنة بالسجل السابق: اسم + حجم متقارب = مكررة محتملة (تُخفى)، اسم فقط = تنبيه
      final primaries = <String, FoundRepo>{};
      final shown = <FoundRepo>[];
      var rejHidden = 0;
      for (final r in res) {
        // مستودع رُفض سابقاً: يُتجاهل (يمكنك إظهاره أو العودة إليه من «قائمة المرفوضة»)
        if (!_showRejected && rejected.contains(DiscoverApi.norm(r.url))) {
          rejHidden++;
          continue;
        }
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
      if (DiscoverApi.lastWarning != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(DiscoverApi.lastWarning!)));
      }
      setState(() {
        _seen = seen;
        _known = known;
        _rejected = rejected;
        _rejHidden = rejHidden;
        _fetched = res.length;
        _knownInFetched = res.where((r) => known.contains(DiscoverApi.norm(r.url))).length;
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
    if (await QueueApi.hasPending()) {
      if (mounted) toast(context, 'يوجد طابور آخر بانتظار البدء؛ انتظر حتى يبدأ ثم أرسل (وإلا يُلغى الأقدم).', error: true);
      return;
    }
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
        items: [
          const DropdownMenuItem(value: allTopics, child: Text('كل التصنيفات')),
          for (final t in topics) DropdownMenuItem(value: t, child: Text(t)),
        ],
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
        items: [for (final n in [0, 5, 20, 50, 100, 500]) DropdownMenuItem(value: n, child: Text(n == 0 ? 'بلا تحديد' : '$n+'))],
        onChanged: (v) => setState(() => minStars = v ?? minStars),
      ),
      SwitchListTile(
        value: recentOnly,
        onChanged: (v) => setState(() => recentOnly = v),
        title: const Text('محدّثة خلال آخر سنتين فقط'),
      ),
      SwitchListTile(
        value: _showRejected,
        onChanged: (v) => setState(() => _showRejected = v),
        title: const Text('إظهار المرفوضة سابقاً في النتائج'),
        subtitle: const Text('مطفأ: يتجاهلها البحث', style: TextStyle(fontSize: 11)),
      ),
      OutlinedButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RejectedScreen())),
        icon: const Icon(Icons.block),
        label: const Padding(padding: EdgeInsets.all(8), child: Text('قائمة المستودعات المرفوضة (للعودة إليها لاحقاً)')),
      ),
      const SizedBox(height: 6),
      FilledButton.icon(
        onPressed: _searching || _running ? null : _search,
        icon: const Icon(Icons.search),
        label: const Padding(padding: EdgeInsets.all(10), child: Text('ابحث')),
      ),
      if (_searching) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
      if (_err != null) Padding(padding: const EdgeInsets.all(8), child: Text(_err!, style: const TextStyle(color: Pal.bad))),
      if (_fetched >= 0 && !_searching)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'جلب GitHub $_fetched مستودعاً: $_knownInFetched مسجّلة سابقاً، $_rejHidden مرفوضة مخفية، ${_hidden.length} مكررة مخفية ← المعروض ${_results.length}',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
      if (_results.isNotEmpty) ...[
        const Divider(height: 28),
        Text('النتائج (${_results.length}) — أُخفيت ${_hidden.length} نسخة مكررة محتملة${_rejHidden > 0 ? ' و$_rejHidden مرفوضة سابقاً' : ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
        _selectBar(),
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

  /// الصالح للتحديد: غير المسجّل سابقاً (والمسجّل معطّل أصلاً)
  List<String> get _selectable => [for (final r in _results) if (!_isKnown(r)) r.fullName];

  Widget _selectBar() {
    final all = _selectable;
    final allOn = all.isNotEmpty && all.every(_selected.contains);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        OutlinedButton.icon(
          onPressed: (_running || all.isEmpty)
              ? null
              : () => setState(() {
                    if (allOn) {
                      _selected.removeAll(all);
                    } else {
                      _selected.addAll(all);
                    }
                  }),
          icon: Icon(allOn ? Icons.deselect : Icons.select_all, size: 18),
          label: Text(allOn ? 'إلغاء تحديد الكل' : 'تحديد الكل (${all.length})'),
        ),
        const SizedBox(width: 10),
        Text('المحدد: ${_selected.length}', style: const TextStyle(color: Pal.lime, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _tile(FoundRepo r) {
    final known = _isKnown(r);
    final rejected = _rejected.contains(DiscoverApi.norm(r.url));
    return _RepoCard(
      r: r,
      known: known,
      rejected: rejected,
      note: _note[r.fullName],
      hiddenN: _hiddenCount[r.fullName] ?? 0,
      state: _state[r.fullName],
      selected: _selected.contains(r.fullName),
      enabled: !(known || _running),
      onChanged: (v) => setState(() => v ? _selected.add(r.fullName) : _selected.remove(r.fullName)),
      onOpen: () => launchUrl(Uri.parse(r.url), mode: LaunchMode.externalApplication),
    );
  }
}


String _starsText(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k' : '$n';

/// بطاقة نتيجة اكتشاف: ترتيب ثابت (عنوان ونجوم، شارات، حالة، ثم الوصف في سطر واحد قابل للتوسيع).
class _RepoCard extends StatefulWidget {
  final FoundRepo r;
  final bool known, rejected, selected, enabled;
  final String? note, state;
  final int hiddenN;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpen;
  const _RepoCard({
    required this.r,
    required this.known,
    required this.rejected,
    required this.selected,
    required this.enabled,
    required this.note,
    required this.state,
    required this.hiddenN,
    required this.onChanged,
    required this.onOpen,
  });

  @override
  State<_RepoCard> createState() => _RepoCardState();
}

class _RepoCardState extends State<_RepoCard> {
  bool _open = false;

  Widget _chip(String text, Color c, {IconData? icon, bool filled = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: filled ? c.withOpacity(0.18) : Colors.transparent,
          border: Border.all(color: c.withOpacity(0.55)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w500)),
        ]),
      );

  Widget _desc(String text) {
    const thin = TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w300, height: 1.5);
    return LayoutBuilder(builder: (ctx, c) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: thin),
        maxLines: 1,
        textDirection: Directionality.of(ctx),
      )..layout(maxWidth: c.maxWidth - 30);
      final overflow = tp.didExceedMaxLines;
      if (!overflow && !_open) return Text(text, style: thin, maxLines: 1);
      return InkWell(
        onTap: () => setState(() => _open = !_open),
        child: _open
            ? Text.rich(TextSpan(children: [
                TextSpan(text: text, style: thin),
                const TextSpan(text: '  ▲', style: TextStyle(color: Pal.lime, fontSize: 11)),
              ]))
            : Row(children: [
                Expanded(child: Text(text, style: thin, maxLines: 1, overflow: TextOverflow.clip)),
                const Text(' •••', style: TextStyle(color: Pal.lime, fontWeight: FontWeight.bold)),
              ]),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final owner = r.fullName.contains('/') ? r.fullName.split('/').first : '';
    final border = widget.selected
        ? Pal.lime
        : widget.known
            ? Pal.ok
            : widget.rejected
                ? Pal.bad
                : Pal.purple;
    final lu = r.license.toUpperCase();
    final gpl = lu.contains('GPL') || lu.contains('MPL') || lu.contains('-SA-');  // حقوق متبادلة
    final topics = r.topics.isEmpty ? <String>[] : r.topics.split(', ').where((e) => e.isNotEmpty).take(4).toList();
    return Card(
      color: Pal.surface,
      shape: Pal.cardShape(border),
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(
            value: widget.selected,
            onChanged: widget.enabled ? (v) => widget.onChanged(v == true) : null,
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      if (owner.isNotEmpty) TextSpan(text: '$owner/', style: const TextStyle(color: Colors.white38, fontWeight: FontWeight.w300)),
                      TextSpan(text: r.repoName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ]),
                    style: const TextStyle(fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                _chip(_starsText(r.stars), Pal.warn, icon: Icons.star_rounded, filled: true),
              ]),
              const SizedBox(height: 7),
              Wrap(spacing: 6, runSpacing: 5, children: [
                _chip(r.license.isEmpty ? 'بلا رخصة' : r.license, gpl ? Pal.warn : Pal.ok, icon: Icons.verified_outlined),
                _chip(r.pushed, Colors.blueGrey.shade200, icon: Icons.update),
                for (final t in topics) _chip(t, Pal.purple),
              ]),
              if (widget.known || widget.rejected || widget.note != null || widget.hiddenN > 0 || widget.state != null) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 5, children: [
                  if (widget.known) _chip('مسجّلة سابقاً', Pal.ok, icon: Icons.check_circle, filled: true),
                  if (widget.rejected) _chip('مرفوضة سابقاً', Pal.bad, icon: Icons.block, filled: true),
                  if (widget.note != null) _chip(widget.note!, Pal.warn, icon: Icons.warning_amber_rounded, filled: true),
                  if (widget.hiddenN > 0) _chip('+${widget.hiddenN} نسخ مشابهة مخفية', Pal.purple, filled: true),
                  if (widget.state != null) _chip(widget.state!, Pal.lime, icon: Icons.arrow_back, filled: true),
                ]),
              ],
              if (r.desc.isNotEmpty) ...[
                const SizedBox(height: 8),
                _desc(r.desc.replaceAll(RegExp(r'\s+'), ' ').trim()),
              ],
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new, size: 20, color: Colors.white54),
            tooltip: 'فتح في GitHub',
            onPressed: widget.onOpen,
          ),
        ]),
      ),
    );
  }
}
