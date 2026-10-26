import 'dart:async';
import 'package:flutter/material.dart';
import '../core/cloudinary.dart';
import '../core/consts.dart';
import '../core/github.dart';
import '../core/license_checker.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../widgets/image_field.dart';
import '../widgets/ui.dart';
import 'test_play_screen.dart';

/// إضافة/تعديل لعبة (يقابل Add_Film.gd بوضع الألعاب).
class GameFormScreen extends StatefulWidget {
  final Map<String, dynamic>? item;
  final bool isFeatured;
  final bool fromPending; // لعبة مستوردة تلقائياً بانتظار الاعتماد
  const GameFormScreen({super.key, this.item, this.isFeatured = false, this.fromPending = false});
  @override
  State<GameFormScreen> createState() => _GameFormScreenState();
}

class _GameFormScreenState extends State<GameFormScreen> {
  final id = TextEditingController();
  final titleAr = TextEditingController();
  final titleEn = TextEditingController();
  final year = TextEditingController();
  final rating = TextEditingController();
  final tags = TextEditingController();
  final desc = TextEditingController();
  final cover = TextEditingController();
  final bg = TextEditingController();
  final play = TextEditingController();
  final dev = TextEditingController();
  final source = TextEditingController();
  String license = allowedLicenses.first;
  String orientation = orientations.first;
  bool featured = false;

  Map<String, dynamic> _orig = {};
  bool get _isNew => widget.item == null;
  bool _busy = false;
  String _status = '';
  LicenseResult? _lic;
  Timer? _timer;

  Map _m(dynamic v) => v is Map ? v : {};

  @override
  void initState() {
    super.initState();
    featured = widget.isFeatured;
    if (widget.item != null) {
      _fill(widget.item!);
    } else {
      final d = Store.draft;
      if (d != null) {
        _fill(d);
        _status = 'تم استرجاع المسودة المحفوظة تلقائياً';
      }
      _nextId();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
    final t = it['category_tags'];
    tags.text = t is List ? t.join(', ') : '';
    desc.text = '${d['description'] ?? ''}';
    cover.text = '${main['poster_url'] ?? ''}';
    bg.text = '${d['background_url'] ?? ''}';
    play.text = '${d['play_url'] ?? ''}';
    dev.text = '${d['developer'] ?? ''}';
    source.text = '${d['source_url'] ?? ''}';
    final lic = '${d['license'] ?? ''}';
    if (allowedLicenses.contains(lic)) license = lic;
    final o = '${d['orientation'] ?? ''}';
    if (orientations.contains(o)) orientation = o;
  }

  Future<void> _nextId() async {
    if (id.text.isNotEmpty || !Store.hasGithub) return;
    try {
      var max = 0;
      for (final file in [gamesFile, featuredFile, pendingFile]) {
        final g = await Github.getJson(file);
        for (final e in Github.asList(g.data)) {
          final v = int.tryParse('${e['id']}') ?? 0;
          if (v > max) max = v;
        }
      }
      if (mounted && id.text.isEmpty) setState(() => id.text = '${max + 1}');
    } catch (_) {}
  }

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
    d['play_url'] = play.text.trim();
    d['developer'] = dev.text.trim();
    d['license'] = license;
    d['source_url'] = source.text.trim();
    d['orientation'] = orientation;
    d['category'] = tagList.isNotEmpty ? tagList.first : '';
    return {
      ..._orig,
      'id': int.tryParse(id.text.trim()) ?? 0,
      'release_year': year.text.trim(),
      'category_tags': tagList,
      'main_scene': main,
      'details_scene': d,
    };
  }

  void _changed() {
    if (!_isNew) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 800), () => Store.saveDraft(_collect()));
  }

  Future<void> _checkLicense() async {
    final url = source.text.trim();
    if (url.isEmpty) {
      toast(context, 'ضع رابط المصدر أولاً', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await LicenseChecker.check(url);
      setState(() {
        _lic = r;
        if (r.allowed && r.spdx != null && allowedLicenses.contains(r.spdx)) license = r.spdx!;
        if (r.developer != null && dev.text.trim().isEmpty) dev.text = r.developer!;
        if (r.description != null && desc.text.trim().isEmpty) desc.text = r.description!;
        if (r.title != null && titleEn.text.trim().isEmpty) titleEn.text = r.title!;
      });
      _changed();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _genBackground() async {
    final c = cover.text.trim();
    if (c.isEmpty) {
      toast(context, 'ضع صورة الغلاف أولاً', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      var p = Cloudinary.parseUrl(c);
      if (p == null || p.cloud != Store.clCloud) {
        final up = await Cloudinary.uploadRemote(c);
        p = (cloud: Store.clCloud, publicId: up.publicId);
      }
      final src = Cloudinary.buildUrl(p.cloud, p.publicId, Cloudinary.blurredBackground);
      final out = await Cloudinary.uploadRemote(src);
      setState(() => bg.text = out.url);
      _changed();
      if (mounted) toast(context, 'تم توليد الخلفية الضبابية ✓');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    final item = _collect();
    final err = validateGame(item);
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
      final g = await Github.getJson(gamesFile);
      final list = Github.asList(g.data);
      final idx = list.indexWhere((e) => '${e['id']}' == '${item['id']}');
      if (idx >= 0) {
        if (_isNew && !await confirm(context, 'الرقم مستخدم', 'يوجد لعبة بنفس الرقم. استبدالها؟', ok: 'استبدال')) {
          setState(() => _busy = false);
          return;
        }
        list[idx] = item;
      } else {
        list.add(item);
      }
      await Github.putJson(gamesFile, list, sha: g.sha, message: 'game ${item['id']}: ${item['main_scene']['title_ar']}');

      final f = await Github.getJson(featuredFile);
      final fl = Github.asList(f.data);
      final before = fl.length;
      final fi = fl.indexWhere((e) => '${e['id']}' == '${item['id']}');
      if (featured) {
        if (fi >= 0) {
          fl[fi] = item;
        } else {
          fl.add(item);
        }
        await Github.putJson(featuredFile, fl, sha: f.sha, message: 'featured ${item['id']}');
      } else if (fi >= 0) {
        fl.removeAt(fi);
        if (fl.length != before) await Github.putJson(featuredFile, fl, sha: f.sha, message: 'unfeature ${item['id']}');
      }
      if (widget.fromPending) {
        final pd = await Github.getJson(pendingFile);
        final pl = Github.asList(pd.data);
        final n0 = pl.length;
        pl.removeWhere((e) => '${e['id']}' == '${item['id']}');
        if (pl.length != n0) await Github.putJson(pendingFile, pl, sha: pd.sha, message: 'approve ${item['id']}');
      }
      if (_isNew) await Store.clearDraft();
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
    final n = titleAr.text;
    if (!await confirm(context, 'حذف اللعبة', 'حذف "$n" نهائياً من القائمتين؟', ok: 'حذف')) return;
    setState(() => _busy = true);
    try {
      for (final file in [gamesFile, featuredFile, pendingFile]) {
        final g = await Github.getJson(file);
        final list = Github.asList(g.data);
        final before = list.length;
        list.removeWhere((e) => '${e['id']}' == id.text.trim());
        if (list.length != before) await Github.putJson(file, list, sha: g.sha, message: 'delete ${id.text}');
      }
      if (!mounted) return;
      toast(context, 'تم الحذف');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _clear() async {
    if (!await confirm(context, 'مسح النموذج', 'مسح كل الحقول والمسودة؟')) return;
    await Store.clearDraft();
    for (final c in [titleAr, titleEn, year, rating, tags, desc, cover, bg, play, dev, source]) {
      c.clear();
    }
    id.clear();
    setState(() {
      _lic = null;
      _orig = {};
    });
    _nextId();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'لعبة جديدة' : (widget.fromPending ? 'مراجعة: ${titleAr.text}' : 'تعديل: ${titleAr.text}')),
        actions: [
          if (_isNew) IconButton(icon: const Icon(Icons.cleaning_services), tooltip: 'مسح', onPressed: _clear),
          if (!_isNew) IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: _busy ? null : _delete),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(padding: const EdgeInsets.all(14), children: [
          if (_busy) const LinearProgressIndicator(),
          if (_status.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_status, style: const TextStyle(color: Pal.warn))),
          Row(children: [
            SizedBox(
              width: 90,
              child: TextField(
                controller: id,
                readOnly: !_isNew,
                keyboardType: TextInputType.number,
                onChanged: (_) => _changed(),
                decoration: const InputDecoration(labelText: 'ID'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: field(titleAr, 'اسم اللعبة (عربي)', onChanged: _changed)),
          ]),
          field(titleEn, 'الاسم بالإنجليزية', onChanged: _changed),
          Row(children: [
            Expanded(child: field(year, 'سنة الإصدار', type: TextInputType.number, onChanged: _changed)),
            const SizedBox(width: 10),
            Expanded(child: field(rating, 'التقييم (0-10)', type: const TextInputType.numberWithOptions(decimal: true), onChanged: _changed)),
          ]),
          field(tags, 'التصنيفات (puzzle, arcade, racing ...)', onChanged: _changed),
          field(desc, 'الوصف', lines: 4, onChanged: _changed),
          ImageField(label: 'صورة الغلاف *', controller: cover, onChanged: _changed),
          ImageField(label: 'صورة الخلفية', controller: bg, onChanged: _changed, previewHeight: 120),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
                onPressed: _genBackground, icon: const Icon(Icons.blur_on), label: const Text('ولّد خلفية ضبابية من الغلاف')),
          ),
          const Divider(height: 30),
          field(play, 'رابط اللعبة (https://.../index.html)', type: TextInputType.url, onChanged: _changed),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                final u = play.text.trim();
                if (!u.startsWith('https://')) {
                  toast(context, 'الرابط يجب أن يبدأ بـ https', error: true);
                  return;
                }
                Navigator.push(context, MaterialPageRoute(builder: (_) => TestPlayScreen(url: u)));
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('جرّب اللعبة'),
            ),
          ),
          const Text('الرخصة والمصدر', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.lime)),
          const SizedBox(height: 8),
          field(source, 'رابط المصدر (مستودع GitHub أو صفحة اللعبة)', type: TextInputType.url, onChanged: _changed),
          FilledButton.tonalIcon(
              onPressed: _checkLicense, icon: const Icon(Icons.verified_user), label: const Text('فحص الرخصة تلقائياً')),
          if (_lic != null)
            Card(
              color: _lic!.allowed ? const Color(0xFF12482B) : const Color(0xFF5A1717),
              shape: Pal.cardShape(_lic!.allowed ? Pal.ok : Pal.bad),
              margin: const EdgeInsets.only(top: 10),
              child: Padding(padding: const EdgeInsets.all(12), child: Text(_lic!.message)),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: license,
            decoration: const InputDecoration(labelText: 'الرخصة'),
            items: [for (final l in allowedLicenses) DropdownMenuItem(value: l, child: Text(l))],
            onChanged: (v) {
              setState(() => license = v ?? license);
              _changed();
            },
          ),
          const SizedBox(height: 10),
          field(dev, 'المطوّر الأصلي', onChanged: _changed),
          DropdownButtonFormField<String>(
            value: orientation,
            decoration: const InputDecoration(labelText: 'اتجاه الشاشة'),
            items: [for (final o in orientations) DropdownMenuItem(value: o, child: Text(o))],
            onChanged: (v) {
              setState(() => orientation = v ?? orientation);
              _changed();
            },
          ),
          SwitchListTile(
            value: featured,
            onChanged: (v) => setState(() => featured = v),
            title: const Text('ضمن الألعاب المميزة'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.cloud_upload),
            label: Padding(padding: const EdgeInsets.all(12), child: Text(widget.fromPending ? 'اعتماد ونشر للاعبين' : 'رفع إلى GitHub')),
          ),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }
}
