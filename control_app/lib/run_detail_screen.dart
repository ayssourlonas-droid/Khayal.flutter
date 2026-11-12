import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'actions_api.dart';
import 'theme.dart';
import 'ui.dart';
import 'import_verdict.dart';

String timeAgo(dynamic iso) {
  final t = DateTime.tryParse('$iso')?.toLocal();
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'الآن';
  if (d.inMinutes < 60) return 'قبل ${d.inMinutes} د';
  if (d.inHours < 24) return 'قبل ${d.inHours} س';
  return 'قبل ${d.inDays} يوم';
}

String fileSize(dynamic b) {
  final n = (b is num) ? b.toDouble() : 0.0;
  if (n >= 1048576) return '${(n / 1048576).toStringAsFixed(1)} MB';
  return '${(n / 1024).toStringAsFixed(0)} KB';
}

// ───────────── تفاصيل تشغيل ─────────────
class RunDetailScreen extends StatefulWidget {
  final Map<String, dynamic> run;
  const RunDetailScreen({super.key, required this.run});
  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  late Map<String, dynamic> run = widget.run;
  List<Map<String, dynamic>> jobs = [];
  final Map<int, List<Map<String, String>>> errors = {};
  List<Map<String, dynamic>> arts = [];
  Verdict? verdict;
  bool loading = true;
  String? err;
  Timer? _timer;

  int get id => run['id'] as int;
  bool get running => run['status'] != 'completed';

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (running) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => loading = true);
    try {
      run = await ActionsApi.run(id);
      jobs = await ActionsApi.jobs(id);
      for (final j in jobs) {
        if (j['status'] == 'completed' && !errors.containsKey(j['id'])) {
          try {
            errors[j['id'] as int] = await ActionsApi.annotations(j['id'] as int);
          } catch (_) {
            errors[j['id'] as int] = [];
          }
        }
      }
      try {
        verdict = await ImportVerdicts.resolve(run, force: true);
      } catch (_) {}
      if (!running) arts = await ActionsApi.artifacts(id);
      err = null;
    } catch (e) {
      err = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _act(Future<void> Function() f, String ok) async {
    try {
      await f();
      if (mounted) toast(context, ok);
      await Future.delayed(const Duration(seconds: 2));
      _load(silent: true);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  IconData _icon(dynamic status, dynamic concl) {
    if (status != 'completed') return Icons.autorenew;
    switch ('$concl') {
      case 'success':
        return Icons.check_circle;
      case 'skipped':
        return Icons.remove_circle_outline;
      case 'cancelled':
        return Icons.cancel;
    }
    return Icons.error;
  }

  Color _color(dynamic status, dynamic concl) {
    if (status != 'completed') return Pal.purple;
    switch ('$concl') {
      case 'success':
        return Pal.ok;
      case 'skipped':
      case 'cancelled':
        return Colors.grey;
    }
    return Pal.bad;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${run['name']} #${run['run_number']}'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(14), children: [
              if (err != null) Text(err!, style: const TextStyle(color: Pal.bad)),
              if (verdict != null) _verdictPanel(verdict!),
              Text(timeAgo(run['created_at']), style: const TextStyle(color: Colors.white60)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 6, children: [
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse('${run['html_url']}'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('فتح في GitHub'),
                ),
                if (running)
                  OutlinedButton.icon(
                      onPressed: () => _act(() => ActionsApi.cancel(id), 'طُلب الإلغاء'),
                      icon: const Icon(Icons.stop_circle),
                      label: const Text('إلغاء'))
                else ...[
                  if (run['conclusion'] == 'failure')
                    OutlinedButton.icon(
                        onPressed: () => _act(() => ActionsApi.rerunFailed(id), 'أُعيد تشغيل الفاشل'),
                        icon: const Icon(Icons.replay),
                        label: const Text('إعادة الفاشل')),
                  OutlinedButton.icon(
                      onPressed: () => _act(() => ActionsApi.rerun(id), 'أُعيد التشغيل'),
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('إعادة الكل')),
                ],
              ]),
              const SizedBox(height: 16),
              if (arts.isNotEmpty) ...[
                const Text('الملفات الناتجة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.lime)),
                for (final a in arts)
                  Card(
                    color: Pal.surface,
                    shape: Pal.cardShape(Pal.ok),
                    child: ListTile(
                      leading: const Icon(Icons.android, color: Pal.ok),
                      title: Text('${a['name']}'),
                      subtitle: Text(a['expired'] == true ? 'منتهية الصلاحية' : 'الحجم المضغوط: ${fileSize(a['size_in_bytes'])}'),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('للتحميل: اضغط «فتح في GitHub» ثم Artifacts أسفل الصفحة.',
                      style: TextStyle(fontSize: 12, color: Colors.white60)),
                ),
                const SizedBox(height: 10),
              ],
              const Text('المراحل', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.lime)),
              for (final j in jobs) _job(j),
            ]),
    );
  }

  Widget _verdictPanel(Verdict v) {
    final c = v.color;
    Widget block(String head, String body) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(head, style: TextStyle(fontWeight: FontWeight.bold, color: c)),
            const SizedBox(height: 3),
            SelectableText(body, style: const TextStyle(fontSize: 14, height: 1.5)),
          ]),
        );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withOpacity(0.13),
        border: Border.all(color: c.withOpacity(0.7), width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          v.level == VLevel.running
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Icon(v.icon, color: c),
          const SizedBox(width: 8),
          Expanded(
              child: Text('${v.label}: ${v.title}',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: c))),
        ]),
        if (v.repoName.isNotEmpty) block('المستودع', 'https://github.com/${v.repoName}'),
        if (v.stage.isNotEmpty && v.level == VLevel.running) block('المرحلة الآن', v.stage),
        if (v.why.isNotEmpty) block('ماذا حدث', v.why),
        if (v.advice.isNotEmpty) block('ما العمل', v.advice),
        if (v.reasons.isNotEmpty) block('تفاصيل الرفض', v.reasons.map((e) => '• $e').join('\n')),
        if (v.warnings.isNotEmpty) block('التحذيرات', v.warnings.map((e) => '• $e').join('\n')),
      ]),
    );
  }

  Widget _note(Map<String, String> a) {
    final lvl = a['level'];
    final color = lvl == 'failure' ? Pal.bad : (lvl == 'warning' ? Pal.warn : Pal.ok);
    final title = a['title'] ?? '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty)
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        if (title.isNotEmpty) const SizedBox(height: 4),
        SelectableText(a['message'] ?? '', style: const TextStyle(fontSize: 12.5, height: 1.45)),
      ]),
    );
  }

  Widget _job(Map<String, dynamic> j) {
    final steps = (j['steps'] is List) ? List<Map<String, dynamic>>.from((j['steps'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e))) : <Map<String, dynamic>>[];
    final c = _color(j['status'], j['conclusion']);
    final errs = errors[j['id']] ?? [];
    return Card(
      color: Pal.surface,
      shape: Pal.cardShape(c),
      margin: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(_icon(j['status'], j['conclusion']), color: c),
        title: Text('${j['name']}'),
        children: [
          for (final s in steps)
            ListTile(
              dense: true,
              leading: Icon(_icon(s['status'], s['conclusion']), size: 18, color: _color(s['status'], s['conclusion'])),
              title: Text('${s['name']}'),
            ),
          for (final a in errs)
            if ((a['title'] ?? '') != 'خيال-نتيجة') _note(a),
        ],
      ),
    );
  }
}
