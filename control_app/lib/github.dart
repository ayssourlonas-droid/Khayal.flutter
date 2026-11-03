import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'store.dart';

class GhFile {
  final dynamic data;
  final String? sha;
  GhFile(this.data, this.sha);
}

class GhException implements Exception {
  final String message;
  GhException(this.message);
  @override
  String toString() => message;
}

/// قراءة/كتابة ملفات JSON في المستودع عبر GitHub Contents API (مثل Github_Manager.gd).
class Github {
  Github._();
  static const _timeout = Duration(seconds: 60);

  static Map<String, String> _headers({bool raw = false}) {
    final t = Store.ghToken;
    return {
      if (t.isNotEmpty) 'Authorization': t.startsWith('ghp_') ? 'token $t' : 'Bearer $t',
      'Accept': raw ? 'application/vnd.github.raw+json' : 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'gamehub-control',
    };
  }

  static Uri _contents(String path, {bool ref = true}) => Uri.https(
        'api.github.com',
        '/repos/${Store.ghOwner}/${Store.ghRepo}/contents/$path',
        ref ? {'ref': Store.ghBranch} : null,
      );

  static String _err(http.Response r) {
    try {
      final j = jsonDecode(r.body);
      if (j is Map && j['message'] != null) return 'GitHub ${r.statusCode}: ${j['message']}';
    } catch (_) {}
    return 'GitHub ${r.statusCode}';
  }

  /// يقرأ ملف JSON. إذا لم يوجد يرجع [] بدون sha.
  static Future<GhFile> getJson(String path) async {
    if (!Store.hasGithub) throw GhException('أدخل إعدادات GitHub أولاً (الإعدادات).');
    final r = await http.get(_contents(path), headers: _headers()).timeout(_timeout);
    if (r.statusCode == 404) return GhFile(<dynamic>[], null);
    if (r.statusCode != 200) throw GhException(_err(r));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final sha = j['sha']?.toString();
    String text;
    final c = (j['content'] ?? '').toString();
    if (c.isEmpty || j['encoding'] == 'none') {
      final rr = await http.get(_contents(path), headers: _headers(raw: true)).timeout(_timeout);
      if (rr.statusCode != 200) throw GhException(_err(rr));
      text = utf8.decode(rr.bodyBytes);
    } else {
      text = utf8.decode(base64Decode(c.replaceAll('\n', '').replaceAll('\r', '')));
    }
    if (text.trim().isEmpty) return GhFile(<dynamic>[], sha);
    return GhFile(jsonDecode(text), sha);
  }

  /// قائمة ألعاب؛ إن كان الملف Dictionary نجمع القوائم داخله (سلوك Godot القديم).
  static List<Map<String, dynamic>> asList(dynamic data) {
    final out = <Map<String, dynamic>>[];
    void add(dynamic v) {
      if (v is Map) out.add(Map<String, dynamic>.from(v));
    }

    if (data is List) {
      data.forEach(add);
    } else if (data is Map) {
      for (final v in data.values) {
        if (v is List) v.forEach(add);
      }
    }
    return out;
  }

  static Future<void> putJson(String path, dynamic data, {String? sha, String? message}) async {
    if (!Store.hasGithub) throw GhException('أدخل إعدادات GitHub أولاً (الإعدادات).');
    final body = base64Encode(utf8.encode(const JsonEncoder.withIndent('  ').convert(data)));
    String? curSha = sha;
    String last = 'فشل غير معروف';
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final r = await http
            .put(
              _contents(path, ref: false),
              headers: {..._headers(), 'Content-Type': 'application/json'},
              body: jsonEncode({
                'message': message ?? 'update $path',
                'content': body,
                'branch': Store.ghBranch,
                if (curSha != null) 'sha': curSha,
              }),
            )
            .timeout(_timeout);
        if (r.statusCode == 200 || r.statusCode == 201) return;
        last = _err(r);
        if (r.statusCode == 409 || r.statusCode == 422) {
          // sha قديم → نجلب الحالي ونعيد المحاولة
          final cur = await getJson(path);
          curSha = cur.sha;
        } else if (r.statusCode == 401 || r.statusCode == 403 || r.statusCode == 404) {
          throw GhException('$last — تحقق من الـ Token وصلاحية الكتابة (Contents: Read and write).');
        }
      } on TimeoutException {
        last = 'انتهت مهلة الاتصال';
      }
      await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
    }
    throw GhException(last);
  }

  static Future<String> testConnection() async {
    final r = await http
        .get(Uri.https('api.github.com', '/repos/${Store.ghOwner}/${Store.ghRepo}'),
            headers: _headers())
        .timeout(_timeout);
    if (r.statusCode != 200) throw GhException(_err(r));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final push = (j['permissions'] is Map) ? j['permissions']['push'] == true : null;
    return 'متصل ✓  ${j['full_name']}  ${push == true ? '(صلاحية كتابة ✓)' : push == false ? '(⚠️ بدون صلاحية كتابة)' : ''}';
  }

  /// استدعاء عام لـ API (للتحقق من الرخصة).
  static Future<http.Response> api(String path) =>
      http.get(Uri.https('api.github.com', path), headers: _headers()).timeout(_timeout);
}
