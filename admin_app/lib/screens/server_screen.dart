import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/consts.dart';
import '../core/github.dart';
import '../widgets/ui.dart';

/// تبويبان: محرر version.json (يقرؤه تطبيق اللاعبين) + محرر JSON خام لأي ملف.
class ServerScreen extends StatelessWidget {
  const ServerScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الإصدار والمحرر'),
          bottom: const TabBar(tabs: [Tab(text: 'الإصدار'), Tab(text: 'JSON خام')]),
        ),
        body: const TabBarView(children: [_VersionTab(), _RawTab()]),
      ),
    );
  }
}

class _VersionTab extends StatefulWidget {
  const _VersionTab();
  @override
  State<_VersionTab> createState() => _VersionTabState();
}

class _VersionTabState extends State<_VersionTab> {
  static const keys = {
    'latest_version': 'آخر إصدار (مثل 1.2.0)',
    'download_url': 'رابط التحميل',
    'whatsapp_url': 'رابط واتساب الدعم',
    'support_email': 'بريد الدعم',
    'app_page_url': 'صفحة التطبيق',
    'feedback_url': 'رابط الملاحظات',
  };
  final c = {for (final k in keys.keys) k: TextEditingController()};
  String mode = 'optional';
  Map<String, dynamic> _all = {};
  String? _sha;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final f = await Github.getJson(versionFile);
      _sha = f.sha;
      _all = f.data is Map ? Map<String, dynamic>.from(f.data) : {};
      for (final k in keys.keys) {
        c[k]!.text = '${_all[k] ?? ''}';
      }
      final m = '${_all['update_mode'] ?? 'optional'}';
      mode = (m == 'forced') ? 'forced' : 'optional';
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final out = {..._all};
      for (final k in keys.keys) {
        out[k] = c[k]!.text.trim();
      }
      out['update_mode'] = mode;
      final cur = await Github.getJson(versionFile);
      await Github.putJson(versionFile, out, sha: cur.sha ?? _sha, message: 'version ${out['latest_version']}');
      if (mounted) toast(context, 'تم الرفع ✓');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(14), children: [
      if (_busy) const LinearProgressIndicator(),
      for (final e in keys.entries) field(c[e.key]!, e.value),
      DropdownButtonFormField<String>(
        value: mode,
        decoration: const InputDecoration(labelText: 'نمط التحديث'),
        items: const [
          DropdownMenuItem(value: 'optional', child: Text('اختياري')),
          DropdownMenuItem(value: 'forced', child: Text('إجباري')),
        ],
        onChanged: (v) => setState(() => mode = v ?? mode),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: _busy ? null : _load, child: const Text('إعادة تحميل'))),
        const SizedBox(width: 10),
        Expanded(child: FilledButton(onPressed: _busy ? null : _save, child: const Text('رفع'))),
      ]),
    ]);
  }
}

class _RawTab extends StatefulWidget {
  const _RawTab();
  @override
  State<_RawTab> createState() => _RawTabState();
}

class _RawTabState extends State<_RawTab> {
  String file = gamesFile;
  final ctl = TextEditingController();
  String? _sha;
  bool _busy = false;

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final f = await Github.getJson(file);
      _sha = f.sha;
      ctl.text = const JsonEncoder.withIndent('  ').convert(f.data);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    dynamic data;
    try {
      data = jsonDecode(ctl.text);
    } catch (e) {
      toast(context, 'JSON غير صالح: $e', error: true);
      return;
    }
    if (!await confirm(context, 'رفع $file', 'سيُستبدل الملف بالكامل. متأكد؟', ok: 'رفع')) return;
    setState(() => _busy = true);
    try {
      await Github.putJson(file, data, sha: _sha, message: 'manual edit $file');
      if (mounted) toast(context, 'تم الرفع ✓');
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        Row(children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: file,
              items: [for (final f in [gamesFile, featuredFile, versionFile]) DropdownMenuItem(value: f, child: Text(f))],
              onChanged: (v) => setState(() => file = v ?? file),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _busy ? null : _load, child: const Text('تحميل')),
          const SizedBox(width: 8),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('رفع')),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: TextField(
            controller: ctl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(hintText: 'اضغط تحميل'),
          ),
        ),
      ]),
    );
  }
}
