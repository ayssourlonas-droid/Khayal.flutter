import 'dart:convert';
import 'package:http/http.dart' as http;
import 'consts.dart';
import 'github.dart';
import 'store.dart';

/// مستودع التطبيقين الذي تُنشر فيه الإصدارات (غير مستودع البيانات khayal-control).
const releaseOwner = 'ayssourlonas-droid';
const releaseRepo = 'Khayal.flutter';

class BuildRelease {
  final int id;
  final String version; // بلا حرف v، مثل 2.1.57 (نفس صيغة PackageInfo في تطبيق اللاعبين)
  final bool prerelease;
  final String apkUrl;
  BuildRelease({required this.id, required this.version, required this.prerelease, required this.apkUrl});
}

/// يقرأ آخر بناء منشور في Releases ويعتمده (يكتب version.json).
/// التوكن يحتاج Contents: Read and write على Khayal.flutter وعلى khayal-control.
class Releases {
  Releases._();
  static const _timeout = Duration(seconds: 40);
  static const apkName = 'khayal.apk';
  static const _base = '/repos/$releaseOwner/$releaseRepo';

  static Map<String, String> _h() {
    final t = Store.ghToken;
    return {
      if (t.isNotEmpty) 'Authorization': t.startsWith('ghp_') ? 'token $t' : 'Bearer $t',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'gamehub-control',
    };
  }

  static String _err(http.Response r) {
    String m = '';
    try {
      final j = jsonDecode(r.body);
      if (j is Map && j['message'] != null) m = ': ${j['message']}';
    } catch (_) {}
    final hint = (r.statusCode == 403 || r.statusCode == 404)
        ? '\nتحقق أن التوكن يشمل $releaseOwner/$releaseRepo بصلاحية Contents: Read and write.'
        : '';
    return 'GitHub ${r.statusCode}$m$hint';
  }

  static int _cmp(String a, String b) {
    final x = a.split('.'), y = b.split('.');
    final n = x.length > y.length ? x.length : y.length;
    for (var i = 0; i < n; i++) {
      final p = i < x.length ? int.tryParse(x[i]) ?? 0 : 0;
      final q = i < y.length ? int.tryParse(y[i]) ?? 0 : 0;
      if (p != q) return p.compareTo(q);
    }
    return 0;
  }

  /// أعلى رقم إصدار له ملف khayal.apk (تجريبي أو معتمد). null إن لم يوجد.
  static Future<BuildRelease?> latestBuild() async {
    if (Store.ghToken.isEmpty) throw GhException('أدخل التوكن أولاً (الإعدادات).');
    final r = await http
        .get(Uri.https('api.github.com', '$_base/releases', {'per_page': '30'}), headers: _h())
        .timeout(_timeout);
    if (r.statusCode != 200) throw GhException(_err(r));
    final list = jsonDecode(r.body);
    if (list is! List) return null;
    BuildRelease? best;
    for (final e in list) {
      if (e is! Map || e['draft'] == true) continue;
      final version = '${e['tag_name']}'.replaceFirst(RegExp(r'^v'), '');
      if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) continue;
      String? apk;
      final assets = e['assets'];
      if (assets is List) {
        for (final a in assets) {
          if (a is Map && a['name'] == apkName) apk = '${a['browser_download_url']}';
        }
      }
      if (apk == null) continue;
      final rel = BuildRelease(
        id: e['id'] as int,
        version: version,
        prerelease: e['prerelease'] == true,
        apkUrl: apk,
      );
      if (best == null || _cmp(rel.version, best.version) > 0) best = rel;
    }
    return best;
  }

  /// يحوّل الإصدار من تجريبي إلى عادي، ثم يكتب latest_version وdownload_url في version.json.
  static Future<void> approve(BuildRelease b) async {
    if (b.prerelease) {
      final r = await http
          .patch(Uri.https('api.github.com', '$_base/releases/${b.id}'),
              headers: {..._h(), 'Content-Type': 'application/json'},
              body: jsonEncode({'prerelease': false, 'make_latest': 'true'}))
          .timeout(_timeout);
      if (r.statusCode != 200) throw GhException(_err(r));
    }
    final cur = await Github.getJson(versionFile);
    final out = cur.data is Map ? Map<String, dynamic>.from(cur.data as Map) : <String, dynamic>{};
    out['latest_version'] = b.version;
    out['download_url'] = b.apkUrl;
    await Github.putJson(versionFile, out, sha: cur.sha, message: 'approve ${b.version}');
  }
}
