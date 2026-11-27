import 'package:flutter/material.dart';
import 'film_consts.dart';
import 'film_form_screen.dart';
import 'film_search_screen.dart';
import 'github.dart';
import 'theme.dart';
import 'ui.dart';

/// مركز الأفلام: قائمة الأفلام المنشورة (data_films.json) مع بحث، وإضافة وتعديل وحذف.
class FilmsHubScreen extends StatefulWidget {
  const FilmsHubScreen({super.key});
  @override
  State<FilmsHubScreen> createState() => _FilmsHubScreenState();
}

class _FilmsHubScreenState extends State<FilmsHubScreen> {
  List<Map<String, dynamic>> _films = [];
  bool _loading = true;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _films = Github.asList((await Github.getJson(filmsFile)).data);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Map _m(dynamic v) => v is Map ? v : {};

  Future<void> _open([Map<String, dynamic>? film]) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => FilmFormScreen(item: film)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = _films.where((f) {
      if (q.isEmpty) return true;
      final main = _m(f['main_scene']);
      return '${main['title_ar'] ?? ''} ${main['title_en'] ?? ''} ${f['id']}'.toLowerCase().contains(q);
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_loading ? 'الأفلام' : 'الأفلام (${_films.length})'),
        actions: [
          IconButton(
              tooltip: 'بحث عن أفلام مرخّصة',
              icon: const Icon(Icons.travel_explore),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const FilmSearchScreen()));
                if (mounted) _load();
              }),
          IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Pal.magenta,
        foregroundColor: Colors.white,
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('فيلم جديد'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 90), children: [
          TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث بالاسم أو الرقم'),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (!_loading && shown.isEmpty)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: Text('لا توجد أفلام بعد. اضغط «فيلم جديد» لإضافة أول فيلم.')),
            ),
          for (final f in shown)
            Card(
              color: Pal.surface,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.movie_rounded)),
                title: Text('${_m(f['main_scene'])['title_ar'] ?? '?'}'),
                subtitle: Text(
                    '#${f['id']} · ${_m(f['details_scene'])['license'] ?? ''} · '
                    '${(_m(f['details_scene'])['audio_tracks'] is List) ? (_m(f['details_scene'])['audio_tracks'] as List).length : 0} صوت · '
                    '${(_m(f['details_scene'])['subtitle_tracks'] is List) ? (_m(f['details_scene'])['subtitle_tracks'] as List).length : 0} ترجمة'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => _open(f),
              ),
            ),
        ]),
      ),
    );
  }
}
