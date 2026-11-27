import 'package:flutter/material.dart';
import 'film_form_screen.dart';
import 'film_search_api.dart';
import 'license_policy.dart';
import 'theme.dart';
import 'ui.dart';

/// بحث عن أفلام مرخّصة في مصادر مفتوحة، مع حكم الرخصة وما يجوز تعديله، ثم نقل الفيلم إلى النموذج.
class FilmSearchScreen extends StatefulWidget {
  const FilmSearchScreen({super.key});
  @override
  State<FilmSearchScreen> createState() => _FilmSearchScreenState();
}

class _FilmSearchScreenState extends State<FilmSearchScreen> {
  final _q = TextEditingController();
  String _source = 'archive';
  bool _loading = false;
  bool _showRejected = false;
  int _minMin = 60; // أقل مدة بالدقائق (0 = الكل): الافتراضي أفلام حقيقية
  String _coll = '';
  String _progress = '';
  List<FilmCandidate> _all = [];
  String _note = '';

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _note = '';
    });
    try {
      _all = _source == 'archive'
          ? await FilmSearchApi.archive(_q.text, collection: _coll)
          : await FilmSearchApi.commons(_q.text);
      if (_all.isEmpty) _note = 'لا نتائج. جرّب كلمات أخرى (بالإنجليزية غالباً).';
      if (mounted) setState(() => _loading = false);
      // فحص المدة الفعلية للمقبولة رخصةً فقط (يوفّر الطلبات)
      await FilmSearchApi.enrich([for (final c in _all) if (c.license.allowed) c], onProgress: (a, b) {
        if (mounted) setState(() => _progress = a >= b ? '' : 'فحص المدة $a/$b');
      });
    } catch (e) {
      _all = [];
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() {
      _loading = false;
      _progress = '';
    });
  }

  Future<void> _use(FilmCandidate c) async {
    setState(() => _loading = true);
    try {
      if (c.source == 'archive' && c.videoUrl.isEmpty) await FilmSearchApi.resolveArchive(c);
      if (!mounted) return;
      if (c.videoUrl.isEmpty) {
        toast(context, 'لم أجد ملف فيديو مباشراً في هذا العنصر', error: true);
      } else {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => FilmFormScreen(prefill: c.toPrefill())));
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Widget _chip(String t, bool ok) => Container(
        margin: const EdgeInsets.only(left: 4, top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: (ok ? Pal.ok : Pal.bad).withOpacity(0.16),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: (ok ? Pal.ok : Pal.bad).withOpacity(0.6)),
        ),
        child: Text('${ok ? '✓' : '✗'} $t', style: const TextStyle(fontSize: 11)),
      );

  String _fmtMin(double m) {
    final t = m.round();
    return t >= 60 ? '${t ~/ 60}س ${t % 60}د' : '$tد';
  }

  Widget _durationBadge(FilmCandidate c) {
    final m = c.durationMin;
    final String t;
    final Color col;
    if (m == null) {
      t = c.source == 'archive' && !c.resolved ? 'جارٍ فحص المدة...' : 'المدة غير معروفة';
      col = Colors.white54;
    } else if (m >= 60) {
      t = '🎬 فيلم طويل · ${_fmtMin(m)}';
      col = Pal.ok;
    } else if (m >= 20) {
      t = '🎞️ فيلم قصير · ${_fmtMin(m)}';
      col = Pal.warn;
    } else {
      t = '⚠️ مقطع قصير · ${_fmtMin(m)}';
      col = Pal.bad;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text('$t${c.downloads > 0 ? '  ·  ⬇ ${c.downloads}' : ''}', style: TextStyle(fontSize: 12, color: col, fontWeight: FontWeight.bold)),
    );
  }

  bool _passMin(FilmCandidate c) => _minMin == 0 || (c.durationMin != null && c.durationMin! >= _minMin);

  Widget _card(FilmCandidate c) {
    final lic = c.license;
    final p = lic.id == null ? null : FilmLicensePolicy.of(lic.id!);
    final ok = lic.allowed && (lic.confidence >= 0.6);
    return Card(
      color: Pal.surface,
      margin: const EdgeInsets.only(bottom: 10),
      shape: Pal.cardShape(ok ? Pal.ok : Pal.bad),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 80,
                height: 110,
                child: c.thumb.isEmpty
                    ? const Icon(Icons.movie)
                    : Image.network(c.thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.movie)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.title.isEmpty ? '؟' : c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                if (c.creator.isNotEmpty) Text(c.creator, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
                if (c.year.isNotEmpty) Text(c.year, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                _durationBadge(c),
                const SizedBox(height: 4),
                Text(
                  ok ? (p?.name ?? lic.id!) : (lic.reason.isEmpty ? 'مرفوضة' : lic.reason),
                  style: TextStyle(fontSize: 12.5, color: ok ? Pal.ok : Pal.bad, fontWeight: FontWeight.bold),
                ),
                if (ok && lic.confidence < 0.9)
                  Text('ثقة الكشف ${(lic.confidence * 100).round()}%: تأكد من صفحة المصدر', style: const TextStyle(fontSize: 11.5, color: Pal.warn)),
              ]),
            ),
          ]),
          if (ok && p != null) ...[
            const SizedBox(height: 6),
            Wrap(children: [for (final o in EditOp.values) _chip(o.label, p.allows(o))]),
            if (p.shareAlike) const Padding(padding: EdgeInsets.only(top: 4), child: Text('⚠️ النسخة المعدلة تُنشر بنفس الرخصة', style: TextStyle(fontSize: 12, color: Pal.warn))),
          ],
          const SizedBox(height: 8),
          Row(children: [
            if (ok)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Pal.magenta, foregroundColor: Colors.white),
                onPressed: _loading ? null : () => _use(c),
                icon: const Icon(Icons.download_done),
                label: const Text('استخدمه في نموذج الفيلم'),
              ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ok = _all.where((c) => c.license.allowed).toList();
    final rejected = _all.length - ok.length;
    final shown = (_showRejected ? _all : ok).where((c) => !c.license.allowed || _passMin(c)).toList();
    final hiddenShort = ok.where((c) => !_passMin(c)).length;
    return Scaffold(
      appBar: AppBar(title: const Text('بحث عن أفلام مرخّصة')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        TextField(
          controller: _q,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: 'اسم أو موضوع (بالإنجليزية أدق)',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(icon: const Icon(Icons.travel_explore), onPressed: _loading ? null : _search),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('Internet Archive'), selected: _source == 'archive', onSelected: (_) => setState(() => _source = 'archive')),
          ChoiceChip(label: const Text('Wikimedia Commons'), selected: _source == 'commons', onSelected: (_) => setState(() => _source = 'commons')),
        ]),
        if (_source == 'archive')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DropdownButtonFormField<String>(
              value: _coll,
              decoration: const InputDecoration(labelText: 'مجموعة الأرشيف'),
              items: [for (final e in FilmSearchApi.archiveCollections.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _coll = v ?? ''),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('المدة:'),
          ChoiceChip(label: const Text('أفلام +60 د'), selected: _minMin == 60, onSelected: (_) => setState(() => _minMin = 60)),
          ChoiceChip(label: const Text('+20 د'), selected: _minMin == 20, onSelected: (_) => setState(() => _minMin = 20)),
          ChoiceChip(label: const Text('الكل'), selected: _minMin == 0, onSelected: (_) => setState(() => _minMin = 0)),
        ]),
        if (_loading || _progress.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const LinearProgressIndicator(), if (_progress.isNotEmpty) Text(_progress, style: const TextStyle(fontSize: 12))])),
        if (!_loading && hiddenShort > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('أُخفي $hiddenShort نتيجة أقصر من $_minMin دقيقة (أو مدتها غير معروفة). اختر «الكل» لإظهارها.', style: const TextStyle(fontSize: 12, color: Colors.white60))),
        if (_note.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(_note)),
        if (_all.isNotEmpty)
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _showRejected,
            onChanged: (v) => setState(() => _showRejected = v),
            title: Text('إظهار المرفوضة ($rejected)'),
          ),
        const SizedBox(height: 4),
        for (final c in shown) _card(c),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('الحكم على الرخصة آلي من بيانات المصدر: افتح صفحة المصدر وتأكد قبل النشر. هذه أداة مساعدة وليست استشارة قانونية.',
              style: TextStyle(fontSize: 12, color: Colors.white54)),
        ),
      ]),
    );
  }
}
