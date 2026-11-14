import 'package:flutter/material.dart';
import 'actions_api.dart';
import 'github.dart';
import 'theme.dart';
import 'ui.dart';

/// يتحكم بإعدادات تضمين الخطوط: يقرأ tools/import_game/fonts_map.json من المستودع ويكتبه.
/// يقرؤه الاستيراد (fonts_local.py) في كل لعبة جديدة؛ وللألعاب الموجودة يوجد زر تشغيل لمرة واحدة.
class FontsScreen extends StatefulWidget {
  const FontsScreen({super.key});
  @override
  State<FontsScreen> createState() => _FontsScreenState();
}

class _FontsScreenState extends State<FontsScreen> {
  static const _path = 'tools/import_game/fonts_map.json';
  static const _purple = Color(0xFFB34DE6);

  // الطرز: المفتاح، الاسم العربي، البديل الافتراضي
  static const _styles = <List<String>>[
    ['cartoon', 'كرتوني', 'Baloo 2'],
    ['modern', 'عصري', 'Inter'],
    ['pixel', 'بكسلي', 'Pixelify Sans'],
    ['fantasy', 'فانتازي', 'Cinzel'],
    ['tech', 'تقني', 'Orbitron'],
    ['mono', 'برمجي', 'JetBrains Mono'],
    ['hand', 'خط يد', 'Caveat'],
    ['serif', 'كلاسيكي', 'Lora'],
  ];

  Map<String, dynamic> _raw = {};
  String? _sha;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool enabled = true;
  bool dropItalic = true;
  bool injectDefault = true;
  String defaultStyle = 'modern';
  int maxFamilies = 3;
  int maxKb = 450;
  Set<int> keepWeights = {400, 700};
  String subsets = 'auto';
  String arabic = 'auto';
  final arabicFamily = TextEditingController(text: 'Tajawal');
  final skip = TextEditingController();
  final fullWeights = TextEditingController();
  final Set<String> activeStyles = {for (final s in _styles) s[0]};
  final Map<String, TextEditingController> styleFont = {
    for (final s in _styles) s[0]: TextEditingController(text: s[2]),
  };
  final List<List<TextEditingController>> pairs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    arabicFamily.dispose();
    skip.dispose();
    fullWeights.dispose();
    for (final c in styleFont.values) {
      c.dispose();
    }
    for (final p in pairs) {
      p[0].dispose();
      p[1].dispose();
    }
    super.dispose();
  }

  List<String> _strList(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : <String>[];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final f = await Github.getJson(_path);
      _sha = f.sha;
      _raw = f.data is Map ? Map<String, dynamic>.from(f.data as Map) : <String, dynamic>{};
      final d = _raw;
      enabled = d['enabled'] != false;
      dropItalic = d['drop_italic'] != false;
      injectDefault = d['inject_default'] != false;
      defaultStyle = _styles.any((s) => s[0] == d['default_style']) ? d['default_style'] as String : 'modern';
      maxFamilies = (d['max_families'] is num) ? (d['max_families'] as num).toInt() : 3;
      maxKb = (d['max_total_kb'] is num) ? (d['max_total_kb'] as num).toInt() : 450;
      if (d['keep_weights'] is List) {
        keepWeights = (d['keep_weights'] as List).whereType<num>().map((e) => e.toInt()).toSet();
        if (keepWeights.isEmpty) keepWeights = {400, 700};
      }
      subsets = ['auto', 'latin', 'all'].contains(d['subsets']) ? d['subsets'] as String : 'auto';
      arabic = ['auto', 'always', 'never'].contains(d['arabic_fallback']) ? d['arabic_fallback'] as String : 'auto';
      arabicFamily.text = (d['arabic_family'] ?? 'Tajawal').toString();
      skip.text = _strList(d['skip']).join('، ');
      fullWeights.text = _strList(d['full_weights']).join('، ');
      // ملف غير موجود: الاستبدال مفتوح لكل الطرز (الافتراضي)
      if (d.containsKey('auto_replace_styles')) {
        activeStyles
          ..clear()
          ..addAll(_strList(d['auto_replace_styles']));
      }
      if (d['style_defaults'] is Map) {
        final m = d['style_defaults'] as Map;
        for (final s in _styles) {
          final v = (m[s[0]] ?? '').toString();
          if (v.isNotEmpty) styleFont[s[0]]!.text = v;
        }
      }
      for (final p in pairs) {
        p[0].dispose();
        p[1].dispose();
      }
      pairs.clear();
      if (d['replace'] is Map) {
        (d['replace'] as Map).forEach((k, v) {
          pairs.add([TextEditingController(text: '$k'), TextEditingController(text: '$v')]);
        });
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  List<String> _split(String t) =>
      t.split(RegExp(r'[,،\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final out = Map<String, dynamic>.from(_raw); // نحافظ على مفاتيح _help وغيرها
      out['enabled'] = enabled;
      out['drop_italic'] = dropItalic;
      out['inject_default'] = injectDefault;
      out['default_style'] = defaultStyle;
      out['max_families'] = maxFamilies;
      out['max_total_kb'] = maxKb;
      out['keep_weights'] = (keepWeights.toList()..sort());
      out['subsets'] = subsets;
      out['arabic_fallback'] = arabic;
      out['arabic_family'] = arabicFamily.text.trim().isEmpty ? 'Tajawal' : arabicFamily.text.trim();
      out['skip'] = _split(skip.text);
      out['full_weights'] = _split(fullWeights.text);
      out['auto_replace_styles'] = [for (final s in _styles) if (activeStyles.contains(s[0])) s[0]];
      out['style_defaults'] = {
        for (final s in _styles)
          s[0]: styleFont[s[0]]!.text.trim().isEmpty ? s[2] : styleFont[s[0]]!.text.trim()
      };
      out['replace'] = {
        for (final p in pairs)
          if (p[0].text.trim().isNotEmpty && p[1].text.trim().isNotEmpty) p[0].text.trim(): p[1].text.trim()
      };
      await Github.putJson(_path, out, sha: _sha, message: 'fonts settings (from Game Control)');
      _raw = out;
      final f = await Github.getJson(_path);
      _sha = f.sha;
      if (mounted) toast(context, 'تم الحفظ ✓ — يسري على الاستيرادات القادمة');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _applyExisting() async {
    final ok = await confirm(
      context,
      'تطبيق على الألعاب الموجودة؟',
      'يشغّل «Localize fonts» على كل الألعاب ويعدّلها ويرفعها. احفظ الإعدادات أولاً. '
          'يمكنك أولاً تشغيل معاينة فقط.',
      ok: 'تعديل فعلي',
    );
    if (!ok) return;
    await _dispatch(false);
  }

  Future<void> _dispatch(bool dry) async {
    try {
      await ActionsApi.dispatch('fonts-existing.yml', {'slug': '', 'dry_run': dry ? 'true' : 'false'});
      if (mounted) toast(context, dry ? 'بدأت المعاينة (انظر ملخص التشغيل في Actions)' : 'بدأ التطبيق على الألعاب');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Widget _card({required IconData icon, required String title, required Color color, required List<Widget> children}) {
    return Card(
      color: Pal.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: Pal.cardShape(color),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: color.withOpacity(0.18), shape: BoxShape.circle),
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          ...children,
        ]),
      ),
    );
  }

  Widget _hint(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t, style: const TextStyle(fontSize: 12, height: 1.5, color: Colors.white60)),
      );

  Widget _stepper(String label, int v, int step, int min, int max, void Function(int) on, {String unit = ''}) {
    return Row(children: [
      Expanded(child: Text(label)),
      IconButton(
          onPressed: v - step >= min ? () => setState(() => on(v - step)) : null,
          icon: const Icon(Icons.remove_circle_outline)),
      SizedBox(width: 62, child: Text('$v$unit', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
      IconButton(
          onPressed: v + step <= max ? () => setState(() => on(v + step)) : null,
          icon: const Icon(Icons.add_circle_outline)),
    ]);
  }

  Widget _dropdown(String value, Map<String, String> items, void Function(String) on) {
    return DropdownButtonFormField<String>(
      value: value,
      isDense: true,
      items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
      onChanged: (v) => setState(() => on(v ?? value)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الخطوط'), actions: [
        IconButton(tooltip: 'إعادة التحميل', icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Pal.bad)),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                    ]),
                  ),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 24), children: [
                  _card(
                    icon: Icons.font_download,
                    title: 'التضمين المحلي',
                    color: _purple,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: enabled,
                        onChanged: (v) => setState(() => enabled = v),
                        title: const Text('تضمين خطوط Google داخل كل لعبة'),
                        subtitle: const Text('عند الإيقاف تبقى الروابط الخارجية كما هي', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  _card(
                    icon: Icons.swap_horiz,
                    title: 'الاستبدال حسب نوع اللعبة',
                    color: const Color(0xFFE7FF14),
                    children: [
                      _hint('كل خط تستعمله اللعبة يُصنَّف (كرتوني، عصري...). الطراز المفعَّل يُستبدل خطه بالبديل المكتوب. '
                          'اسم الخط يبقى كما هو في كود اللعبة ولا يتغير شيء فيه.'),
                      for (final s in _styles)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            Switch(
                              value: activeStyles.contains(s[0]),
                              onChanged: (v) => setState(() => v ? activeStyles.add(s[0]) : activeStyles.remove(s[0])),
                            ),
                            SizedBox(width: 64, child: Text(s[1], style: const TextStyle(fontWeight: FontWeight.w600))),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: styleFont[s[0]],
                                enabled: activeStyles.contains(s[0]),
                                decoration: const InputDecoration(hintText: 'اسم خط من Google Fonts'),
                              ),
                            ),
                          ]),
                        ),
                    ],
                  ),
                  _card(
                    icon: Icons.add_circle_outline,
                    title: 'ألعاب بلا خطوط',
                    color: const Color(0xFFE91E63),
                    children: [
                      _hint('اللعبة التي تستعمل خطوط النظام فقط (Arial وsans-serif...) يُضمَّن لها خط من القائمة أعلاه، '
                          'فتظهر بنفس الشكل على كل الهواتف دون أي اتصال خارجي. بقواعد بسيطة بلا ذكاء اصطناعي: '
                          'بكسلي إن وُجد image-rendering، وبرمجي إن كانت الخطوط monospace، وإلا الطراز أدناه.'),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: injectDefault,
                        onChanged: (v) => setState(() => injectDefault = v),
                        title: const Text('حقن خط افتراضي'),
                      ),
                      _dropdown(defaultStyle, {for (final s in _styles) s[0]: '${s[1]} (${styleFont[s[0]]!.text})'},
                          (v) => defaultStyle = v),
                    ],
                  ),
                  _card(
                    icon: Icons.rule,
                    title: 'استبدال خاص لخط معيّن',
                    color: const Color(0xFFFF9800),
                    children: [
                      _hint('له الأولوية على الطراز. مثال: Fredoka One ← Baloo 2'),
                      for (var i = 0; i < pairs.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Expanded(child: TextField(controller: pairs[i][0], decoration: const InputDecoration(hintText: 'الخط الأصلي'))),
                            const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_back, size: 16)),
                            Expanded(child: TextField(controller: pairs[i][1], decoration: const InputDecoration(hintText: 'البديل'))),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Pal.bad),
                              onPressed: () => setState(() {
                                pairs[i][0].dispose();
                                pairs[i][1].dispose();
                                pairs.removeAt(i);
                              }),
                            ),
                          ]),
                        ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: () => setState(() => pairs.add([TextEditingController(), TextEditingController()])),
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة استبدال'),
                        ),
                      ),
                    ],
                  ),
                  _card(
                    icon: Icons.tune,
                    title: 'الحجم والتقليص',
                    color: const Color(0xFF42A5F5),
                    children: [
                      _stepper('أقصى عدد عائلات خطوط', maxFamilies, 1, 1, 8, (v) => maxFamilies = v),
                      _stepper('أقصى حجم للخطوط', maxKb, 50, 100, 2000, (v) => maxKb = v, unit: ' KB'),
                      const SizedBox(height: 6),
                      const Text('الأوزان المُبقاة (الباقي يُرسم بأقرب وزن):', style: TextStyle(fontSize: 13)),
                      Wrap(spacing: 8, children: [
                        for (final w in const [300, 400, 500, 600, 700, 800, 900])
                          FilterChip(
                            label: Text('$w'),
                            selected: keepWeights.contains(w),
                            onSelected: (v) => setState(() {
                              if (v) {
                                keepWeights.add(w);
                              } else if (keepWeights.length > 1) {
                                keepWeights.remove(w);
                              }
                            }),
                          ),
                      ]),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: dropItalic,
                        onChanged: (v) => setState(() => dropItalic = v),
                        title: const Text('إسقاط الخط المائل'),
                        subtitle: const Text('يرسمه المتصفح مائلاً بنفسه', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(height: 4),
                      const Text('أجزاء الحروف'),
                      const SizedBox(height: 4),
                      _dropdown(subsets, const {
                        'auto': 'تلقائي (اللاتيني + ما تستعمله اللعبة)',
                        'latin': 'اللاتيني فقط',
                        'all': 'الكل',
                      }, (v) => subsets = v),
                      const SizedBox(height: 10),
                      TextField(
                        controller: fullWeights,
                        decoration: const InputDecoration(
                            labelText: 'عائلات تحتفظ بكل أوزانها', hintText: 'مثال: Poppins، Roboto'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: skip,
                        decoration: const InputDecoration(
                            labelText: 'عائلات تُترك على Google (لا تُضمَّن)', hintText: 'مثال: Material Icons'),
                      ),
                    ],
                  ),
                  _card(
                    icon: Icons.translate,
                    title: 'العربية',
                    color: const Color(0xFF26A69A),
                    children: [
                      _hint('خط عربي احتياطي يُضاف لنفس أسماء العائلات، فيظهر النص العربي بخط متناسق.'),
                      _dropdown(arabic, const {
                        'auto': 'تلقائي (إن وُجد عربي في اللعبة)',
                        'always': 'دائماً',
                        'never': 'أبداً',
                      }, (v) => arabic = v),
                      const SizedBox(height: 10),
                      TextField(controller: arabicFamily, decoration: const InputDecoration(labelText: 'الخط العربي')),
                    ],
                  ),
                  _card(
                    icon: Icons.history,
                    title: 'الألعاب الموجودة',
                    color: Pal.ok,
                    children: [
                      _hint('الإعدادات تسري على الاستيرادات القادمة. لتطبيقها على الألعاب المنشورة حالياً شغّل المعاينة أولاً ثم التطبيق. '
                          'احفظ قبل ذلك.'),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _dispatch(true),
                            icon: const Icon(Icons.visibility, size: 18),
                            label: const Text('معاينة'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _applyExisting,
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('تطبيق'),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ]),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Pal.surface,
          border: Border(top: BorderSide(color: Color(0x33B34DE6))),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_loading || _saving || _error != null) ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: const Padding(padding: EdgeInsets.all(10), child: Text('حفظ في المستودع')),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
