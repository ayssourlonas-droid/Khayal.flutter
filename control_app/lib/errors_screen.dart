import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'errors_api.dart';
import 'theme.dart';
import 'ui.dart';

/// أخطاء تطبيق خيال من هواتف اللاعبين: مجمّعة بالتشابه، الأحدث أولاً.
/// يظهر نوع الخطأ ومكان وقوعه وعدد المرات والأجهزة المتأثرة وطرازاتها وإصدارات أندرويد.
class ErrorsScreen extends StatefulWidget {
  const ErrorsScreen({super.key});
  @override
  State<ErrorsScreen> createState() => _ErrorsScreenState();
}

class _ErrorsScreenState extends State<ErrorsScreen> {
  int days = 30;
  bool all = false; // false = غير المحلولة فقط
  bool loading = true;
  String? err;
  ErrorsData? data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      err = null;
    });
    try {
      final r = await ErrorsApi.fetch(days: days, all: all);
      if (mounted) setState(() => data = r);
    } catch (e) {
      if (mounted) setState(() => err = '$e');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _act(AppError e, String action) async {
    if (action == 'delete' && !await confirm(context, 'حذف الخطأ؟', 'يُحذف هذا الخطأ وكل تفاصيله نهائياً.', ok: 'احذف')) return;
    try {
      await ErrorsApi.act(e.fp, action);
      if (mounted) toast(context, action == 'resolve' ? 'عُلّم كمحلول' : (action == 'reopen' ? 'أُعيد فتحه' : 'حُذف'));
      _load();
    } catch (x) {
      if (mounted) toast(context, '$x', error: true);
    }
  }

  Widget _chip(String t, {Color? color, IconData? icon}) => Container(
        margin: const EdgeInsets.only(left: 6, top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: (color ?? Pal.purple).withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: (color ?? Pal.purple).withOpacity(0.6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color ?? Pal.purple), const SizedBox(width: 4)],
          Text(t, style: TextStyle(fontSize: 12, color: color ?? Colors.white70)),
        ]),
      );

  Widget _card(AppError e) {
    final top = e.stack.split('\n').where((l) => l.trim().isNotEmpty).take(1).join();
    return Card(
      color: Pal.surface,
      shape: Pal.cardShape(e.resolved ? null : (e.fatal ? Pal.bad : Pal.warn)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Icon(e.resolved ? Icons.check_circle : (e.fatal ? Icons.error : Icons.bug_report),
              color: e.resolved ? Pal.ok : (e.fatal ? Pal.bad : Pal.warn)),
          title: Text(e.type, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.msg, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
            Wrap(children: [
              _chip('${e.n} مرة', icon: Icons.repeat),
              _chip('${e.devices} جهاز', icon: Icons.phone_android, color: e.devices > 1 ? Pal.warn : null),
              if (e.ver.isNotEmpty) _chip('v${e.ver}', icon: Icons.sell),
              if (e.fatal) _chip('غير ملتقَط', color: Pal.bad),
              _chip(e.last, icon: Icons.schedule),
            ]),
          ]),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (e.ctx.isNotEmpty) Text('اللعبة / السياق: ${e.ctx}', style: const TextStyle(color: Pal.lime)),
            if (top.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text('مكان الوقوع:', style: TextStyle(color: Colors.white54, fontSize: 12)),
              SelectableText(top, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ],
            if (e.models.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('الأجهزة المتأثرة:', style: TextStyle(color: Colors.white54, fontSize: 12)),
              for (final m in e.models)
                Text('• ${m.model.isEmpty ? '؟' : m.model} — Android ${m.android.isEmpty ? '؟' : m.android}  ×${m.n}',
                    style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 10),
            const Text('تتبّع كامل:', style: TextStyle(color: Colors.white54, fontSize: 12)),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
              child: SelectableText(e.stack.isEmpty ? '(لا يوجد)' : e.stack,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            ),
            const SizedBox(height: 4),
            Text('أول ظهور: ${e.first}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('نسخ للمطوّر'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: e.report()));
                  if (mounted) toast(context, 'نُسخت التفاصيل');
                },
              ),
              OutlinedButton.icon(
                icon: Icon(e.resolved ? Icons.undo : Icons.check, size: 16),
                label: Text(e.resolved ? 'إعادة فتح' : 'حُلّ'),
                onPressed: () => _act(e, e.resolved ? 'reopen' : 'resolve'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Pal.bad),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('حذف'),
                onPressed: () => _act(e, 'delete'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    return Scaffold(
      appBar: AppBar(
        title: Text(d == null ? 'أخطاء خيال' : 'أخطاء خيال (${d.open} مفتوح)'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: Row(children: [
            ChoiceChip(
              label: const Text('غير المحلولة'),
              selected: !all,
              onSelected: (_) {
                all = false;
                _load();
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('الكل'),
              selected: all,
              onSelected: (_) {
                all = true;
                _load();
              },
            ),
            const Spacer(),
            DropdownButton<int>(
              value: days,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 7, child: Text('7 أيام')),
                DropdownMenuItem(value: 30, child: Text('30 يوماً')),
                DropdownMenuItem(value: 90, child: Text('90 يوماً')),
              ],
              onChanged: (v) {
                days = v ?? 30;
                _load();
              },
            ),
          ]),
        ),
        if (loading) const LinearProgressIndicator(),
        Expanded(
          child: err != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(err!, textAlign: TextAlign.center)))
              : (d == null || d.errors.isEmpty)
                  ? Center(
                      child: loading
                          ? const SizedBox.shrink()
                          : const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('لا توجد أخطاء في هذه الفترة 🎉\n(الأخطاء تُحفظ 30 يوماً ثم تُحذف تلقائياً)',
                                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                            ))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(10),
                        children: [for (final e in d.errors) _card(e)],
                      ),
                    ),
        ),
      ]),
    );
  }
}
