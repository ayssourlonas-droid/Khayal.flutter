import 'dart:async';
import 'package:flutter/material.dart';
import 'actions_api.dart';
import 'consts.dart';
import 'github.dart';
import 'license_checker.dart';
import 'store.dart';
import 'theme.dart';
import 'image_editor_screen.dart';
import 'image_field.dart';
import 'ui.dart';
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
    d['type'] = (d['type'] ?? 'web').toString().isEmpty ? 'web' : d['type'];
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

  /// يفتح محرر الغلاف على شاشة رسم إزالة النصوص (Cloudinary). عند الاعتماد: يُستبدل رابط الغلاف بالنسخة النظيفة،
  /// والخلفية الضبابية تُولَّد من الصورة النظيفة (حتى لا يظهر أثر النص ولو ضبابياً) عبر Action بلا Cloudinary.
  Future<void> _removeText() async {
    final orig = cover.text.trim();
    if (orig.isEmpty) {
      toast(context, 'ضع صورة الغلاف أولاً', error: true);
      return;
    }
    final out = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => ImageEditorScreen(url: orig, startDrawing: true)));
    if (out == null || !mounted) return;
    setState(() => cover.text = out);
    _changed();
    toast(context, 'تم اعتماد الغلاف المنظّف ✓');
    final gid = id.text.trim();
    // نعيد توليدها إن كانت فارغة أو مولَّدة آلياً سابقاً (bg/<id>.webp)؛ الخلفية التي رفعتها يدوياً لا تُمسّ.
    final b = bg.text.trim();
    if ((b.isEmpty || b.contains('/bg/')) && int.tryParse(gid) != null && int.parse(gid) > 0 && out.startsWith('https://')) {
      try {
        await ActionsApi.dispatch('make-bg.yml', {'game_id': gid, 'cover_url': out});
        final u = Uri.tryParse(play.text.trim());
        final origin = (u != null && u.hasScheme && u.host.isNotEmpty) ? '${u.scheme}://${u.host}' : 'https://khayal-control.pages.dev';
        setState(() => bg.text = '$origin/bg/$gid.webp');
        _changed();
        if (mounted) toast(context, 'بدأ توليد الخلفية الضبابية من الغلاف النظيف (دقيقة أو دقيقتان)');
      } catch (e) {
        if (mounted) toast(context, 'تعذّر بدء الخلفية: $e', error: true);
      }
    }
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

  /// حذف جذري: يُشغَّل workflow باسم delete-game.yml فيمسح السجلات والمجلد وفهرس الاستيراد وصفحة الحقوق
  /// في دفعة واحدة، فتصبح اللعبة كأنها لم تُستورد.
  Future<void> _delete() async {
    final n = titleAr.text;
    if (!await confirm(
        context,
        'حذف اللعبة من جذورها',
        'سيُحذف "$n" نهائياً: من القوائم ومن GitHub وCloudflare (كل ملفاتها)، ويمكن استيرادها من جديد لاحقاً فقط. لا تراجع عن هذا.',
        ok: 'احذف نهائياً')) return;
    setState(() => _busy = true);
    try {
      await ActionsApi.dispatch('delete-game.yml', {
        'game_id': id.text.trim(),
        'play_url': play.text.trim(),
      });
      if (!mounted) return;
      toast(context, 'بدأ الحذف الجذري؛ يكتمل خلال دقيقة تقريباً (تابعه في GitHub ← Actions ← Delete game)');
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

  Widget _section(String title, IconData icon, Color c) => sectionHeader(title, icon, c);

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
          _section('بيانات اللعبة', Icons.sports_esports, Pal.purple),
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
          _section('الصور', Icons.photo_library, const Color(0xFF29B6F6)),
          // الغلاف والخلفية جنباً إلى جنب، بمعاينة كاملة بلا قص
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: ImageField(
                    label: 'الغلاف *', controller: cover, onChanged: _changed, aspect: 470 / 700, accent: Pal.purple)),
            const SizedBox(width: 10),
            Expanded(
                child: ImageField(
                    label: 'الخلفية', controller: bg, onChanged: _changed, aspect: 1080 / 1920, accent: const Color(0xFF26C6DA))),
          ]),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(foregroundColor: Pal.warn),
            onPressed: _removeText,
            icon: const Icon(Icons.draw),
            label: const Text('إزالة نصوص من الغلاف (ارسم)'),
          ),
          const SizedBox(height: 14),
          _section('التشغيل', Icons.play_circle, Pal.ok),
          field(play, 'رابط اللعبة (https://.../index.html)', type: TextInputType.url, onChanged: _changed),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: goStyle.copyWith(padding: const WidgetStatePropertyAll(EdgeInsets.all(14))),
              onPressed: () {
                final u = play.text.trim();
                if (!u.startsWith('https://')) {
                  toast(context, 'الرابط يجب أن يبدأ بـ https', error: true);
                  return;
                }
                Navigator.push(context, MaterialPageRoute(builder: (_) => TestPlayScreen(url: u)));
              },
              icon: const Icon(Icons.play_arrow, size: 26),
              label: const Text('جرّب اللعبة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 18),
          _section('الرخصة والمصدر', Icons.verified_user, Pal.lime),
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
            style: FilledButton.styleFrom(backgroundColor: Pal.magenta, foregroundColor: Colors.white),
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
