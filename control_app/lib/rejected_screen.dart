import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'actions_api.dart';
import 'discover_api.dart';
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

  List<Map<String, dynamic>> get _shown {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((e) => '${e['repo']} ${e['reason']}'.toLowerCase().contains(q)).toList();
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
                onPressed: _busy || _sel.isEmpty ? null : _retry,
                icon: const Icon(Icons.replay),
                label: Text('أعد محاولة المحدد (${_sel.length})'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
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
