import 'package:flutter/material.dart';
import 'stats_api.dart';
import 'theme.dart';
import 'ui.dart';

/// أكثر الألعاب فتحاً (من عدّاد Worker؛ يُحسب فتح الصفحة الرئيسية للعبة فقط).
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
      final r = await StatsApi.fetch(days);
      if (mounted) setState(() => items = r);
    } catch (e) {
      if (mounted) setState(() => err = '$e');
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final maxV = items.isEmpty ? 1 : items.first.plays.clamp(1, 1 << 30);
    final total = items.fold<int>(0, (a, b) => a + b.plays);
    return Scaffold(
      appBar: AppBar(title: const Text('إحصاءات اللعب'), actions: [
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
        if (!loading && err == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Align(alignment: Alignment.centerRight, child: Text('إجمالي مرات الفتح: $total')),
          ),
        Expanded(
          child: items.isEmpty && !loading && err == null
              ? const Center(child: Text('لا بيانات بعد'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final it = items[i];
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
                  },
                ),
        ),
      ]),
    );
  }
}
