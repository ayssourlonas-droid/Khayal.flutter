import 'dart:convert';
import 'package:http/http.dart' as http;
import 'github.dart';
import 'consts.dart';
import 'name_key.dart';
import 'store.dart';

class FoundRepo {
  final String fullName, url, desc, license, topics;
  final int stars;
  final String pushed;
  final int sizeKb;
  FoundRepo(this.fullName, this.url, this.desc, this.license, this.stars, this.pushed, this.topics,
      this.sizeKb);
  String get repoName => fullName.contains('/') ? fullName.split('/').last : fullName;
  String get key => nameKey(repoName);
}

/// سجل الأسماء السابقة: key + الحجم (إن عُرف) لمقارنة الدفعات القادمة.
class SeenEntry {
  final String key;
  final int sizeKb;
  final String label;
  SeenEntry(this.key, this.sizeKb, this.label);
}

/// يبحث في GitHub عن مستودعات ألعاب ويب برخص مسموحة (البحث فقط؛ الفحص النهائي يتم في خط الاستيراد).
class DiscoverApi {
  DiscoverApi._();

  // SPDX ← مفتاح الرخصة في بحث GitHub
  static const licenseKeys = {
    'MIT': 'mit',
    'Apache-2.0': 'apache-2.0',
    'BSD-2-Clause': 'bsd-2-clause',
    'BSD-3-Clause': 'bsd-3-clause',
    'CC0-1.0': 'cc0-1.0',
    'CC-BY-4.0': 'cc-by-4.0',
    'GPL-3.0': 'gpl-3.0',
    'ISC': 'isc',
    'Zlib': 'zlib',
  };

  static Map<String, String> _h() {
    final t = Store.ghToken;
    return {
      if (t.isNotEmpty) 'Authorization': t.startsWith('ghp_') ? 'token $t' : 'Bearer $t',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'gamehub-control',
    };
  }

  static String norm(String u) {
    var s = u.trim().toLowerCase();
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    if (s.endsWith('.git')) s = s.substring(0, s.length - 4);
    return s;
  }

  /// ملف المستودعات المرفوضة (يكتبه record_rejection.py بعد كل رفض).
  static const rejectedFile = 'data_import_rejected.json';

  static Future<List<Map<String, dynamic>>> rejectedList() async {
    try {
      final d = await Github.getJson(rejectedFile);
      return Github.asList(d.data);
    } catch (_) {
      return [];
    }
  }

  static Future<Set<String>> rejectedSources() async =>
      {for (final e in await rejectedList()) norm('${e['url'] ?? ''}')};

  /// روابط المصدر المسجّلة سابقاً (منشورة + مميزة + للمراجعة).
  static Future<Set<String>> knownSources() async {
    final out = <String>{};
    for (final f in [gamesFile, featuredFile, pendingFile]) {
      try {
        final d = await Github.getJson(f);
        for (final g in Github.asList(d.data)) {
          final ds = g['details_scene'];
          if (ds is Map && ds['source_url'] != null) out.add(norm(ds['source_url'].toString()));
        }
      } catch (_) {}
    }
    return out;
  }

  /// السجل المحفوظ (data_import_index.json) + أسماء الألعاب المسجلة سابقاً من روابط مصدرها (بلا حجم).
  static Future<List<SeenEntry>> seenEntries() async {
    final out = <SeenEntry>[];
    final haveUrl = <String>{};
    try {
      final d = await Github.getJson('data_import_index.json');
      for (final e in Github.asList(d.data)) {
        final k = (e['key'] ?? '').toString();
        if (k.isEmpty) continue;
        out.add(SeenEntry(k, (e['size'] is int) ? e['size'] as int : 0, (e['repo'] ?? k).toString()));
        haveUrl.add(norm('https://github.com/${e['repo'] ?? ''}'));
      }
    } catch (_) {}
    for (final f in [gamesFile, featuredFile, pendingFile]) {
      try {
        final d = await Github.getJson(f);
        for (final g in Github.asList(d.data)) {
          final ds = g['details_scene'];
          final u = (ds is Map ? (ds['source_url'] ?? '') : '').toString();
          if (u.isEmpty || haveUrl.contains(norm(u))) continue;
          final name = u.split('/').where((x) => x.isNotEmpty).last;
          out.add(SeenEntry(nameKey(name), 0, name));
        }
      } catch (_) {}
    }
    return out;
  }

  static Future<List<FoundRepo>> search({
    String name = '',
    required String topic,
    required int minStars,
    required bool recentOnly,
    String? onlyLicense,
  }) async {
    final lics = onlyLicense == null ? licenseKeys.keys.toList() : [onlyLicense];
    final found = <String, FoundRepo>{};
    final since = DateTime.now().subtract(const Duration(days: 730));
    final sinceStr =
        '${since.year}-${since.month.toString().padLeft(2, '0')}-${since.day.toString().padLeft(2, '0')}';
    for (final lic in lics) {
      final base = name.trim().isEmpty ? 'topic:$topic' : '${name.trim()} in:name,description';
      final q = '$base license:${licenseKeys[lic]} stars:>=$minStars archived:false fork:false'
          '${recentOnly ? ' pushed:>=$sinceStr' : ''}';
      final uri = Uri.https('api.github.com', '/search/repositories',
          {'q': q, 'sort': 'stars', 'order': 'desc', 'per_page': '15'});
      final r = await http.get(uri, headers: _h()).timeout(const Duration(seconds: 30));
      if (r.statusCode == 403 || r.statusCode == 429) {
        throw GhException('تجاوزت حد البحث في GitHub. انتظر دقيقة ثم أعد المحاولة (يساعد وجود التوكن).');
      }
      if (r.statusCode != 200) throw GhException('GitHub ${r.statusCode}');
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final items = (j is Map && j['items'] is List) ? j['items'] as List : [];
      for (final it in items) {
        if (it is! Map) continue;
        final full = (it['full_name'] ?? '').toString();
        if (full.isEmpty) continue;
        final spdx = it['license'] is Map ? (it['license']['spdx_id'] ?? '').toString() : '';
        found[full] = FoundRepo(
          full,
          (it['html_url'] ?? 'https://github.com/$full').toString(),
          (it['description'] ?? '').toString(),
          spdx,
          (it['stargazers_count'] ?? 0) as int,
          (it['pushed_at'] ?? '').toString().split('T').first,
          ((it['topics'] is List) ? (it['topics'] as List).take(4).join(', ') : ''),
          (it['size'] is int) ? it['size'] as int : 0,
        );
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
    final list = found.values.toList()..sort((a, b) => b.stars.compareTo(a.stars));
    return list;
  }
}
