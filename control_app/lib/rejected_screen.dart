import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'actions_api.dart';
import 'discover_api.dart';
import 'queue_api.dart';
import 'github.dart';
import 'theme.dart';
import 'ui.dart';

/// المستودعات التي رفضها الاستيراد. يتجاهلها الاكتشاف، ويمكنك العودة إليها بعد تطوير أدوات المعالجة
/// (إعادة محاولة بالطابور) أو حذفها من القائمة.
class RejectedScreen extends StatefulWidget {
  const RejectedScreen({super.key});
  @override
  State<RejectedScreen> createState() => _RejectedScreenState();
}

class _RejectedScreenState extends State<RejectedScreen> {
  List<Map<String, dynamic>> _items = [];
  final Set<String> _sel = {};
  String _q = '';
  String _cat = ''; // تصنيف السبب المحدد للتصفية ('' = الكل)
  bool _loading = true;
  bool _busy = false;

  static const _maxQueue = 30;
  static const _skip = '[skip ci] [CF-Pages-Skip]';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final l = await DiscoverApi.rejectedList();
      l.sort((a, b) => '${b['date'] ?? ''}'.compareTo('${a['date'] ?? ''}'));
      _items = l;
      _sel.removeWhere((u) => !_items.any((e) => '${e['url']}' == u));
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  static const _fixableTag = '★ قد تنجح الآن';

  /// تصنيف لسبب الرفض بالكلمات المفتاحية (النص حرّ، فالتصنيف للمراجعة السريعة فقط). الترتيب مهم: الأخصّ أولاً.
  static String _category(Map e) {
    final r = '${e['reason'] ?? ''}'.toLowerCase();
    if (r.contains('ليست لعبة') || r.contains('لا تستقبل أي إدخال')) return 'ليست لعبة';
    if (r.contains('رخص') || r.contains('license') || r.contains('gpl')) return 'رخصة';
    if (r.contains('لم أجد نسخة ويب')) return 'لا نسخة ويب';
    if (r.contains('فشل البناء')) return 'فشل البناء';
    if (r.contains('خادم') || r.contains('قاعدة بيانات') || r.contains('(ws)') || r.contains('socket')) return 'تحتاج خادماً';
    if (r.contains('تتجاوز 25mb') || r.contains('حجم') || r.contains('كبير')) return 'حجم';
    if (r.contains('تعطّل الاستيراد')) return 'تعطّل الاستيراد';
    if (r.contains('فارغ') || r.contains('لا تعمل') || r.contains('خطأ') || r.contains('404')) return 'لا تعمل / فارغة';
    if (r.contains('مكرر')) return 'مكررة';
    return 'أخرى';
  }

  /// أسباب عالجتها تحسينات 23 نوفمبر (فرض أدوات البناء، وسلسلة بدائل npm، وتعطّل بلا تقرير، وقاعدة WebGL،
  /// وفحص الحجم بعد ضغط الوسائط): تستحق إعادة المحاولة. تقدير وليس ضماناً.
  static bool _fixable(Map e) {
    final r = '${e['reason'] ?? ''}';
    return r.contains('رمز 127') ||
        r.contains('تعطّل الاستيراد') ||
        r.contains('الصفحة فارغة بعد') ||
        r.contains("'npm', 'ci'") ||
        r.contains("'yarn', 'install'") ||
        r.contains("'pnpm'") ||
        r.contains('تتجاوز 25MB');
  }

  static const _hints = {
    'لا نسخة ويب': 'لا index.html ولا أمر بناء: غالباً مشروع Unity/Godot مصدري أو أداة. جرّب تحديد subdir أو build_cmd عند الاستيراد اليدوي، وإلا اتركها.',
    'فشل البناء': 'فشل npm/yarn/pnpm. رمز 127 يعني غياب أداة البناء (عولج). غير ذلك يحتاج فحص سجل التشغيل.',
    'لا تعمل / فارغة': 'الصفحة بيضاء أو بلا أي رسم. بعضها كان بسبب قاعدة WebGL القديمة وعولج. أعد المحاولة.',
    'ليست لعبة': 'الصفحة لا تستقبل إدخالاً. غالباً عرض أو أداة؛ اتركها.',
    'تحتاج خادماً': 'لعبة جماعية أو تحتاج قاعدة بيانات؛ لا تعمل كموقع ثابت. اتركها.',
    'حجم': 'ملفات فوق حد Cloudflare (25MB للملف). فحص الحجم يجري الآن بعد ضغط الوسائط، فأعد المحاولة؛ الفيديو الكبير يبقى مرفوضاً.',
    'تعطّل الاستيراد': 'تعطّل قبل إنتاج تقرير. صار يُكتب تقرير بالسبب، فأعد المحاولة لنرى السبب الحقيقي.',
    'رخصة': 'رخصة غير مسموحة (NC/ND/AGPL أو بلا رخصة). اتركها.',
  };

  Map<String, int> get _cats {
    final m = <String, int>{};
    for (final e in _items) {
      final c = _category(e);
      m[c] = (m[c] ?? 0) + 1;
    }
    return m;
  }

  int get _fixableCount => _items.where(_fixable).length;

  List<Map<String, dynamic>> get _shown {
    final q = _q.trim().toLowerCase();
    return _items.where((e) {
      if (_cat == _fixableTag) {
        if (!_fixable(e)) return false;
      } else if (_cat.isNotEmpty && _category(e) != _cat) {
        return false;
      }
      return q.isEmpty || '${e['repo']} ${e['reason']}'.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _retry() async {
    if (_sel.isEmpty) return;
    if (_sel.length > _maxQueue) {
      toast(context, 'الحد الأقصى $_maxQueue مستودعاً في الطابور الواحد؛ قلّل التحديد.', error: true);
      return;
    }
    if (!await confirm(
        context,
        'إعادة المحاولة',
        'سيُرسل ${_sel.length} مستودعاً إلى طابور الاستيراد (واحداً بعد الآخر على خادم GitHub) بأحدث أدوات المعالجة. '
            'ما ينجح يُحذف تلقائياً من هذه القائمة، وما يُرفض يبقى فيها بسبب جديد.',
        ok: 'أرسل للطابور')) return;
    if (await QueueApi.hasPending()) {
      if (mounted) toast(context, 'يوجد طابور آخر بانتظار البدء؛ انتظر حتى يبدأ ثم أرسل (وإلا يُلغى الأقدم).', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ActionsApi.dispatch('import-queue.yml', {
        'urls': _sel.join('\n'),
        'orientation': 'portrait',
        'prune': 'smart',
        'media': 'safe',
        'ai_test': 'no',
      });
      if (mounted) {
        toast(context, 'أُرسلت ${_sel.length} إلى الطابور ✓ تابع النتائج في تبويب السجل');
        _sel.clear();
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove() async {
    if (_sel.isEmpty) return;
    if (!await confirm(context, 'حذف من القائمة',
        'سيُحذف ${_sel.length} مستودعاً من قائمة المرفوضة، فقد يظهر ثانيةً في نتائج الاكتشاف.',
        ok: 'احذف')) return;
    setState(() => _busy = true);
    try {
      final f = await Github.getJson(DiscoverApi.rejectedFile);
      final all = Github.asList(f.data);
      all.removeWhere((e) => _sel.contains('${e['url']}'));
      await Github.putJson(DiscoverApi.rejectedFile, all, sha: f.sha, message: 'rejected: remove ${_sel.length} $_skip');
      _sel.clear();
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final list = _shown;
    return Scaffold(
      appBar: AppBar(
        title: Text('المرفوضة (${_items.length})'),
        actions: [IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load)],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث بالاسم أو بالسبب'),
          ),
        ),
        if (_items.isNotEmpty)
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                if (_fixableCount > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                    child: ChoiceChip(
                      label: Text('$_fixableTag ($_fixableCount)'),
                      selected: _cat == _fixableTag,
                      onSelected: (v) => setState(() => _cat = v ? _fixableTag : ''),
                    ),
                  ),
                for (final c in (_cats.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                    child: ChoiceChip(
                      label: Text('${c.key} (${c.value})'),
                      selected: _cat == c.key,
                      onSelected: (v) => setState(() => _cat = v ? c.key : ''),
                    ),
                  ),
              ],
            ),
          ),
        if (_cat.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(
                    _cat == _fixableTag
                        ? 'رُفضت بأسباب عالجتها التحسينات الأخيرة؛ أعد محاولتها (حتى $_maxQueue في الطابور الواحد). تقدير وليس ضماناً.'
                        : (_hints[_cat] ?? ''),
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          for (final e in _shown.take(_maxQueue)) {
                            _sel.add('${e['url']}');
                          }
                        }),
                child: Text('حدّد أول $_maxQueue'),
              ),
            ]),
          ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: list.isEmpty && !_loading
              ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('لا توجد مستودعات مرفوضة مسجّلة بعد.\nتُسجَّل تلقائياً كلما رفض الاستيراد مستودعاً.', textAlign: TextAlign.center)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final e = list[i];
                    final url = '${e['url']}';
                    final att = int.tryParse('${e['attempts'] ?? 1}') ?? 1;
                    return Card(
                      shape: Pal.cardShape(),
                      child: CheckboxListTile(
                        value: _sel.contains(url),
                        onChanged: _busy ? null : (v) => setState(() => v == true ? _sel.add(url) : _sel.remove(url)),
                        title: Text('${e['repo']}', style: const TextStyle(fontSize: 14)),
                        subtitle: Text(
                          '${e['reason'] ?? ''}\n${e['license'] == null || '${e['license']}'.isEmpty ? '' : '${e['license']} • '}'
                          '${e['date'] ?? ''}${att > 1 ? ' • رُفضت $att مرات' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        secondary: IconButton(
                          icon: const Icon(Icons.open_in_new, size: 20),
                          onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: goStyle,
                onPressed: _busy || _sel.isEmpty ? null : _retry,
                icon: const Icon(Icons.replay),
                label: Text('أعد محاولة المحدد (${_sel.length})'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Pal.bad, side: BorderSide(color: Pal.bad.withOpacity(0.6))),
              onPressed: _busy || _sel.isEmpty ? null : _remove,
              icon: const Icon(Icons.delete_outline),
              label: const Text('حذف'),
            ),
          ]),
        ),
      ),
    );
  }
}
