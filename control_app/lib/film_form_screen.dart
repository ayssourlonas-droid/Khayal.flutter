import 'package:flutter/material.dart';
import 'actions_api.dart';
import 'film_consts.dart';
import 'github.dart';
import 'image_field.dart';
import 'license_detect.dart';
import 'license_policy.dart';
import 'theme.dart';
import 'ui.dart';

/// صف مسار (صوت أو ترجمة): لغة + عنوان اختياري + رابط https.
class _TrackRow {
  String lang;
  final title = TextEditingController();
  final url = TextEditingController();
  _TrackRow(this.lang);
  void dispose() {
    title.dispose();
    url.dispose();
  }
}

/// إضافة/تعديل فيلم. الفيديو يُرفع مرة واحدة بلا صوت، والأصوات والترجمات مسارات منفصلة لتوفير المساحة.
class FilmFormScreen extends StatefulWidget {
  final Map<String, dynamic>? item;
  /// سجل أولي من البحث: يملأ النموذج لكنه يبقى «فيلماً جديداً».
  final Map<String, dynamic>? prefill;
  const FilmFormScreen({super.key, this.item, this.prefill});
  @override
  State<FilmFormScreen> createState() => _FilmFormScreenState();
}

class _FilmFormScreenState extends State<FilmFormScreen> {
  final id = TextEditingController();
  final titleAr = TextEditingController();
  final titleEn = TextEditingController();
  final year = TextEditingController();
  final rating = TextEditingController();
  final minutes = TextEditingController();
  final tags = TextEditingController();
  final desc = TextEditingController();
  final cover = TextEditingController();
  final bg = TextEditingController();
  final video = TextEditingController();
  final credit = TextEditingController();
  final source = TextEditingController();
  final licenseUrl = TextEditingController();
  final licProbe = TextEditingController();
  LicenseDetection? _det;
  String license = allowedFilmLicenses.first;
  final List<_TrackRow> _audios = [];
  final List<_TrackRow> _subs = [];

  Map<String, dynamic> _orig = {};
  bool get _isNew => widget.item == null;
  bool _busy = false;
  String _status = '';

  Map _m(dynamic v) => v is Map ? v : {};

  @override
  void initState() {
    super.initState();
    if (widget.item != null) {
      _fill(widget.item!);
    } else {
      if (widget.prefill != null) _fill(widget.prefill!);
      _nextId();
    }
  }

  @override
  void dispose() {
    for (final r in [..._audios, ..._subs]) {
      r.dispose();
    }
    super.dispose();
  }

  void _fillTracks(List<_TrackRow> out, dynamic src) {
    if (src is! List) return;
    for (final t in src) {
      final m = _m(t);
      final lang = '${m['lang'] ?? ''}';
      final r = _TrackRow(filmLangs.containsKey(lang) ? lang : filmLangs.keys.first);
      r.title.text = '${m['title'] ?? ''}';
      r.url.text = '${m['url'] ?? ''}';
      out.add(r);
    }
  }

  void _fill(Map<String, dynamic> it) {
    _orig = Map<String, dynamic>.from(it);
    final main = _m(it['main_scene']);
    final d = _m(it['details_scene']);
    id.text = '${it['id'] ?? ''}';
    titleAr.text = '${main['title_ar'] ?? ''}';
    titleEn.text = '${main['title_en'] ?? ''}';
    year.text = '${it['release_year'] ?? ''}';
    final r = main['app_rating'];
    rating.text = (r == null || r == 0 || r == 0.0) ? '' : '$r';
    minutes.text = '${d['duration_min'] ?? ''}';
    final t = it['category_tags'];
    tags.text = t is List ? t.join(', ') : '';
    desc.text = '${d['description'] ?? ''}';
    cover.text = '${main['poster_url'] ?? ''}';
    bg.text = '${d['background_url'] ?? ''}';
    video.text = '${d['video_url'] ?? ''}';
    credit.text = '${d['credit'] ?? ''}';
    source.text = '${d['source_url'] ?? ''}';
    licenseUrl.text = '${d['license_url'] ?? ''}';
    final lic = '${d['license'] ?? ''}';
    if (allowedFilmLicenses.contains(lic)) license = lic;
    _fillTracks(_audios, d['audio_tracks']);
    // الترجمة القديمة subtitle_url تُعرض كمسار واحد
    _fillTracks(_subs, d['subtitle_tracks']);
    final old = '${d['subtitle_url'] ?? ''}'.trim();
    if (_subs.isEmpty && old.startsWith('https://')) {
      final r = _TrackRow(filmLangs.keys.first);
      r.url.text = old;
      _subs.add(r);
    }
  }

  Future<void> _nextId() async {
    if (id.text.isNotEmpty) return;
    try {
      var max = 0;
      final g = await Github.getJson(filmsFile);
      for (final e in Github.asList(g.data)) {
        final v = int.tryParse('${e['id']}') ?? 0;
        if (v > max) max = v;
      }
      if (mounted && id.text.isEmpty) setState(() => id.text = '${max + 1}');
    } catch (_) {}
  }

  List<Map<String, String>> _tracksOut(List<_TrackRow> rows) => [
        for (final r in rows)
          if (r.url.text.trim().isNotEmpty)
            {'lang': r.lang, if (r.title.text.trim().isNotEmpty) 'title': r.title.text.trim(), 'url': r.url.text.trim()},
      ];

  Map<String, dynamic> _collect() {
    final tagList = tags.text.split(RegExp(r'[,،]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final main = Map<String, dynamic>.from(_m(_orig['main_scene']));
    final d = Map<String, dynamic>.from(_m(_orig['details_scene']));
    main['title_ar'] = titleAr.text.trim();
    main['title_en'] = titleEn.text.trim();
    main['app_rating'] = double.tryParse(rating.text.trim()) ?? 0.0;
    main['poster_url'] = cover.text.trim();
    d['description'] = desc.text.trim();
    d['background_url'] = bg.text.trim();
    d['video_url'] = video.text.trim();
    d['duration_min'] = int.tryParse(minutes.text.trim()) ?? 0;
    d['credit'] = credit.text.trim();
    d['license'] = license;
    d['license_url'] = licenseUrl.text.trim();
    d['source_url'] = source.text.trim();
    d['category'] = tagList.isNotEmpty ? tagList.first : '';
    d['audio_tracks'] = _tracksOut(_audios);
    d['subtitle_tracks'] = _tracksOut(_subs);
    d.remove('subtitle_url'); // استُبدل بـ subtitle_tracks
    return {
      ..._orig,
      'id': int.tryParse(id.text.trim()) ?? 0,
      'release_year': year.text.trim(),
      'category_tags': tagList,
      'main_scene': main,
      'details_scene': d,
    };
  }

  Future<void> _save() async {
    final item = _collect();
    final err = validateFilm(item);
    if (err.isNotEmpty) {
      toast(context, '⚠️ $err', error: true);
      return;
    }
    if ((item['id'] as int) <= 0) {
      toast(context, 'رقم ID غير صالح', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _status = 'جارٍ الرفع إلى GitHub...';
    });
    try {
      final g = await Github.getJson(filmsFile);
      final list = Github.asList(g.data);
      final idx = list.indexWhere((e) => '${e['id']}' == '${item['id']}');
      if (idx >= 0) {
        if (_isNew && !await confirm(context, 'الرقم مستخدم', 'يوجد فيلم بنفس الرقم. استبداله؟', ok: 'استبدال')) {
          setState(() => _busy = false);
          return;
        }
        list[idx] = item;
      } else {
        list.add(item);
      }
      await Github.putJson(filmsFile, list, sha: g.sha, message: 'film ${item['id']}: ${item['main_scene']['title_ar']}');
      if (!mounted) return;
      toast(context, 'تم الرفع ✓');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _status = '$e');
        toast(context, '$e', error: true);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'حذف الفيلم', 'سيُحذف "${titleAr.text}" من قائمة الأفلام (لا تُحذف ملفات الفيديو من مكان استضافتها).',
        ok: 'احذف')) return;
    setState(() => _busy = true);
    try {
      final g = await Github.getJson(filmsFile);
      final list = Github.asList(g.data);
      list.removeWhere((e) => '${e['id']}' == id.text.trim());
      await Github.putJson(filmsFile, list, sha: g.sha, message: 'delete film ${id.text.trim()}');
      if (!mounted) return;
      toast(context, 'تم الحذف ✓');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _tracksEditor(String title, IconData icon, Color c, List<_TrackRow> rows, String urlHint) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sectionHeader(title, icon, c),
      for (var i = 0; i < rows.length; i++)
        Card(
          color: Pal.surface,
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: rows[i].lang,
                    decoration: const InputDecoration(labelText: 'اللغة'),
                    items: [for (final e in filmLangs.entries) DropdownMenuItem(value: e.key, child: Text('${e.value} (${e.key})'))],
                    onChanged: (v) => setState(() => rows[i].lang = v ?? rows[i].lang),
                  ),
                ),
                IconButton(
                  tooltip: 'حذف المسار',
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => setState(() => rows.removeAt(i).dispose()),
                ),
              ]),
              const SizedBox(height: 8),
              field(rows[i].title, 'عنوان يظهر للاعب (اختياري)'),
              field(rows[i].url, urlHint, type: TextInputType.url),
            ]),
          ),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.tonalIcon(
          onPressed: () => setState(() => rows.add(_TrackRow(rows.isEmpty ? 'ar' : 'en'))),
          icon: const Icon(Icons.add),
          label: const Text('إضافة مسار'),
        ),
      ),
      const SizedBox(height: 14),
    ]);
  }

  /// ترجمة آلية على GitHub (workflow: translate-subs.yml): المصدر ملف ترجمة أو صوت، واللغات الهدف تختارها.
  Future<void> _translateDialog() async {
    final id0 = id.text.trim();
    if (int.tryParse(id0) == null) {
      toast(context, 'احفظ الفيلم أولاً (يلزم رقم صالح)', error: true);
      return;
    }
    final sources = <MapEntry<String, String>>[
      for (final r in _subs)
        if (r.url.text.trim().startsWith('https://')) MapEntry('ترجمة: ${filmLangs[r.lang] ?? r.lang}', r.url.text.trim()),
      for (final r in _audios)
        if (r.url.text.trim().startsWith('https://')) MapEntry('صوت (تفريغ بـ Whisper): ${filmLangs[r.lang] ?? r.lang}', r.url.text.trim()),
    ];
    final custom = TextEditingController();
    var src = sources.isEmpty ? '' : sources.first.value;
    final targets = <String>{'ar'};
    var engine = 'nllb';
    var whisper = 'small';
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('ترجمة آلية عبر GitHub'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('احفظ الفيلم أولاً ليُعرف السجل. قد تستغرق العملية من دقائق إلى ساعات، وتعمل في الخلفية على GitHub.',
                  style: TextStyle(fontSize: 12.5, color: Colors.white70)),
              const SizedBox(height: 10),
              if (sources.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: sources.any((e) => e.value == src) ? src : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'المصدر'),
                  items: [for (final e in sources) DropdownMenuItem(value: e.value, child: Text(e.key, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => set(() => src = v ?? src),
                ),
              TextField(controller: custom, decoration: const InputDecoration(labelText: 'أو رابط آخر (srt / vtt / صوت)')),
              const SizedBox(height: 10),
              const Text('اللغات الهدف'),
              Wrap(spacing: 6, children: [
                for (final e in filmLangs.entries)
                  FilterChip(
                    label: Text(e.value),
                    selected: targets.contains(e.key),
                    onSelected: (v) => set(() => v ? targets.add(e.key) : targets.remove(e.key)),
                  ),
              ]),
              DropdownButtonFormField<String>(
                value: engine,
                decoration: const InputDecoration(labelText: 'المحرك'),
                items: const [
                  DropdownMenuItem(value: 'nllb', child: Text('NLLB-200 (محلي وقوي)')),
                  DropdownMenuItem(value: 'google', child: Text('Google (احتياط)')),
                ],
                onChanged: (v) => set(() => engine = v ?? engine),
              ),
              DropdownButtonFormField<String>(
                value: whisper,
                decoration: const InputDecoration(labelText: 'Whisper (للمصدر الصوتي)'),
                items: const [
                  DropdownMenuItem(value: 'tiny', child: Text('tiny — الأسرع')),
                  DropdownMenuItem(value: 'base', child: Text('base')),
                  DropdownMenuItem(value: 'small', child: Text('small — متوازن')),
                  DropdownMenuItem(value: 'medium', child: Text('medium — الأدق والأبطأ')),
                ],
                onChanged: (v) => set(() => whisper = v ?? whisper),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ابدأ الترجمة')),
          ],
        ),
      ),
    );
    final url = custom.text.trim().isNotEmpty ? custom.text.trim() : src;
    custom.dispose();
    if (go != true) return;
    if (!url.startsWith('https://')) {
      if (mounted) toast(context, 'اختر مصدراً برابط https', error: true);
      return;
    }
    if (targets.isEmpty) {
      if (mounted) toast(context, 'اختر لغة هدف واحدة على الأقل', error: true);
      return;
    }
    try {
      await ActionsApi.dispatch('translate-subs.yml', {
        'film_id': id0,
        'source_url': url,
        'targets': targets.join(','),
        'engine': engine,
        'whisper_model': whisper,
      });
      if (mounted) toast(context, 'بدأت الترجمة على GitHub (Actions ← Translate subtitles). تُضاف المسارات إلى الفيلم تلقائياً عند الانتهاء؛ أعد فتح الفيلم بعدها.');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  /// ما يجوز تعديله وما يجب الالتزام به للرخصة المختارة.
  Widget _policyCard() {
    final p = FilmLicensePolicy.of(license);
    if (p == null) return const SizedBox.shrink();
    Widget chip(String t, bool ok) => Container(
          margin: const EdgeInsets.only(left: 4, top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: (ok ? Pal.ok : Pal.bad).withOpacity(0.16),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: (ok ? Pal.ok : Pal.bad).withOpacity(0.6)),
          ),
          child: Text('${ok ? '✓' : '✗'} $t', style: const TextStyle(fontSize: 12)),
        );
    return Card(
      color: Pal.surface,
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          Wrap(children: [for (final o in EditOp.values) chip(o.label, p.allows(o))]),
          const SizedBox(height: 6),
          for (final n in p.notes) Text('• $n', style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
          const SizedBox(height: 6),
          FilledButton.tonalIcon(
            onPressed: () => setState(() => credit.text = FilmLicensePolicy.creditText(
                  title: titleEn.text.trim().isEmpty ? titleAr.text.trim() : titleEn.text.trim(),
                  creator: credit.text.trim(),
                  licenseId: license,
                  licenseUrl: licenseUrl.text.trim(),
                )),
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('اكتب سطر الاعتماد تلقائياً'),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'فيلم جديد' : 'تعديل: ${titleAr.text}'),
        actions: [
          if (!_isNew) IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: _busy ? null : _delete),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(padding: const EdgeInsets.all(14), children: [
          if (_busy) const LinearProgressIndicator(),
          if (_status.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_status, style: const TextStyle(color: Pal.warn))),
          sectionHeader('بيانات الفيلم', Icons.movie, Pal.purple),
          Row(children: [
            SizedBox(
              width: 90,
              child: TextField(
                controller: id,
                readOnly: !_isNew,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ID'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: field(titleAr, 'اسم الفيلم (عربي)')),
          ]),
          field(titleEn, 'الاسم بالإنجليزية'),
          Row(children: [
            Expanded(child: field(year, 'سنة الإصدار', type: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(child: field(minutes, 'المدة (دقيقة)', type: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(child: field(rating, 'التقييم (0-10)', type: const TextInputType.numberWithOptions(decimal: true))),
          ]),
          field(tags, 'التصنيفات (drama, comedy, animation ...)'),
          field(desc, 'القصة', lines: 4),
          sectionHeader('الصور', Icons.photo_library, const Color(0xFF29B6F6)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: ImageField(label: 'الغلاف *', controller: cover, onChanged: () {}, aspect: 470 / 700, accent: Pal.purple)),
            const SizedBox(width: 10),
            Expanded(child: ImageField(label: 'الخلفية', controller: bg, onChanged: () {}, aspect: 1080 / 1920, accent: const Color(0xFF26C6DA))),
          ]),
          const SizedBox(height: 14),
          sectionHeader('الصورة (الفيديو بلا صوت)', Icons.play_circle, Pal.ok),
          field(video, 'رابط الفيديو المباشر https://... (mp4 / webm / mkv)', type: TextInputType.url),
          const SizedBox(height: 6),
          _tracksEditor('مسارات الصوت', Icons.audiotrack, Pal.lime, _audios, 'رابط الصوت https://... (m4a / opus)'),
          _tracksEditor('مسارات الترجمة', Icons.closed_caption, Pal.warn, _subs, 'رابط الترجمة https://... (srt / vtt)'),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(foregroundColor: Pal.info),
              onPressed: _busy ? null : _translateDialog,
              icon: const Icon(Icons.translate),
              label: const Text('ترجمة آلية عبر GitHub'),
            ),
          ),
          const SizedBox(height: 14),
          sectionHeader('الرخصة والاعتماد', Icons.verified_user, Pal.lime),
          field(licProbe, 'ألصق رابط الرخصة أو نصها لكشفها تلقائياً', type: TextInputType.url),
          FilledButton.tonalIcon(
            onPressed: () {
              final d = LicenseDetector.detect('${licProbe.text} ${licenseUrl.text} ${source.text}');
              setState(() {
                _det = d;
                if (d.allowed && d.id != null) license = d.id!;
              });
            },
            icon: const Icon(Icons.manage_search),
            label: const Text('كشف الرخصة'),
          ),
          if (_det != null)
            Card(
              color: _det!.allowed ? const Color(0xFF12482B) : const Color(0xFF5A1717),
              margin: const EdgeInsets.only(top: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_det!.allowed
                    ? '✓ ${_det!.id} (ثقة ${(_det!.confidence * 100).round()}%)${_det!.reason.isEmpty ? '' : '\n${_det!.reason}'}'
                    : '✗ ${_det!.reason}'),
              ),
            ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: license,
            decoration: const InputDecoration(labelText: 'الرخصة'),
            items: [for (final l in allowedFilmLicenses) DropdownMenuItem(value: l, child: Text(l))],
            onChanged: (v) => setState(() => license = v ?? license),
          ),
          _policyCard(),
          const SizedBox(height: 10),
          field(credit, 'سطر الاعتماد (المنتج/الصانع، مثل: Blender Foundation)'),
          field(source, 'رابط المصدر (صفحة الفيلم التي تثبت الرخصة)', type: TextInputType.url),
          field(licenseUrl, 'رابط نص الرخصة (اختياري)', type: TextInputType.url),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Pal.magenta, foregroundColor: Colors.white),
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.cloud_upload),
            label: const Padding(padding: EdgeInsets.all(12), child: Text('رفع إلى GitHub')),
          ),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }
}
