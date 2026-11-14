import 'package:flutter/material.dart';
import 'stats_api.dart';
import 'theme.dart';
import 'ui.dart';

/// إحصاءات خيال: الأجهزة المجهولة (نشطة/جديدة/إجمالي) وأكثر الألعاب فتحاً.
/// (مصدرها Worker؛ يُحسب فتح الصفحة الرئيسية للعبة فقط، والأجهزة بمعرّف عشوائي لا يدل على صاحبه.)
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int days = 7;
  bool loading = true;
  String? err;
  List<PlayStat> items = [];
  DeviceStats? dev;

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
      final r = await StatsApi.fetchAll(days);
      if (mounted) {
        setState(() {
          items = r.games;
          dev = r.devices;
        });
      }
    } catch (e) {
      if (mounted) setState(() => err = '$e');
    }
    if (mounted) setState(() => loading = false);
  }

  String get _period => days == 1 ? 'اليوم' : (days == 7 ? 'آخر 7 أيام' : 'آخر 30 يوماً');

  Widget _tile(String label, int value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: Pal.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.6)),
        ),
        child: Column(children: [
          Text('$value', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
      ),
    );
  }

  List<Widget> _devicesSection() {
    final d = dev;
    if (d == null) {
      return [
        Card(
          color: Pal.surface,
          shape: Pal.cardShape(),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text('عدّاد الأجهزة غير مفعّل في الـWorker بعد (حدّثه بالنسخة الجديدة ونفّذ schema3.sql).',
                style: TextStyle(color: Colors.white70)),
          ),
        ),
        const SizedBox(height: 12),
      ];
    }
    final shown = d.daily.take(7).toList();
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: sectionHeader('الأجهزة ($_period)', Icons.devices, Pal.teal),
      ),
      Row(children: [
        _tile('أجهزة نشطة', d.active, Pal.purple),
        _tile('أجهزة جديدة', d.fresh, Colors.greenAccent),
        _tile('الإجمالي منذ البداية', d.total, Colors.amber),
      ]),
      const SizedBox(height: 8),
      Card(
        color: Pal.surface,
        shape: Pal.cardShape(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('حسب اليوم', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            if (shown.isEmpty) const Text('لا بيانات بعد', style: TextStyle(color: Colors.white54)),
            for (final x in shown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(child: Text(x.day, style: const TextStyle(color: Colors.white70))),
                  Text('نشط ${x.active}'),
                  const SizedBox(width: 14),
                  Text('جديد ${x.fresh}', style: const TextStyle(color: Colors.greenAccent)),
                ]),
              ),
            if (d.versions.isNotEmpty) ...[
              const Divider(height: 20, color: Colors.white12),
              const Text('الإصدارات المستعملة', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final v in d.versions)
                  Chip(
                    label: Text('${v.ver} · ${v.n}', style: const TextStyle(fontSize: 12)),
                    backgroundColor: Pal.surface2,
                    visualDensity: VisualDensity.compact,
                  ),
              ]),
            ],
            const SizedBox(height: 8),
            const Text(
              'الرقم تقريبي: من يحذف التطبيق أو يمسح بياناته ثم يثبّته يُحسب جهازاً جديداً، ومن لا يتصل بالإنترنت لا يظهر.',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  Widget _gameCard(int i, PlayStat it, int maxV) {
    return Card(
      color: Pal.surface,
      shape: Pal.cardShape(),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${i + 1}. ${it.slug}', style: const TextStyle(fontWeight: FontWeight.bold))),
            Text('${it.plays}'),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: it.plays / maxV,
              minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(Pal.purple),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxV = items.isEmpty ? 1 : items.first.plays.clamp(1, 1 << 30);
    final total = items.fold<int>(0, (a, b) => a + b.plays);
    final ready = !loading && err == null;
    return Scaffold(
      appBar: AppBar(title: const Text('الإحصاءات'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('اليوم')),
              ButtonSegment(value: 7, label: Text('7 أيام')),
              ButtonSegment(value: 30, label: Text('30 يوماً')),
            ],
            selected: {days},
            onSelectionChanged: (s) {
              days = s.first;
              _load();
            },
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (err != null) Padding(padding: const EdgeInsets.all(14), child: Text(err!, style: const TextStyle(color: Pal.bad))),
        Expanded(
          child: !ready
              ? const SizedBox.shrink()
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    ..._devicesSection(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('أكثر الألعاب فتحاً — إجمالي مرات الفتح: $total',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    if (items.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('لا بيانات ألعاب بعد'))),
                    for (var i = 0; i < items.length; i++) _gameCard(i, items[i], maxV),
                  ],
                ),
        ),
      ]),
    );
  }
}
