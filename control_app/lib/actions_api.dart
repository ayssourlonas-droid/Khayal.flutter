import 'dart:convert';
import 'package:http/http.dart' as http;
import 'github.dart' show GhException;
import 'store.dart';

/// تحكم بـ GitHub Actions (تشغيل workflow، متابعة التشغيلات، إلغاء، إعادة، أخطاء، ملفات ناتجة).
/// التوكن يحتاج على مستودع المشاريع: Actions (Read and write) .
class ActionsApi {
  ActionsApi._();
  static const _timeout = Duration(seconds: 40);

  static Map<String, String> _h() {
    final t = Store.ghToken;
    return {
      if (t.isNotEmpty) 'Authorization': t.startsWith('ghp_') ? 'token $t' : 'Bearer $t',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'gamehub-control',
    };
  }

  static String get _base => '/repos/${Store.acOwner}/${Store.acRepo}';
  static Uri _u(String path, [Map<String, String>? q]) => Uri.https('api.github.com', '$_base$path', q);

  static void _need() {
    if (Store.ghToken.isEmpty || Store.acRepo.isEmpty) {
      throw GhException('أدخل التوكن ومستودع المشاريع في الإعدادات أولاً.');
    }
  }

  static String _err(http.Response r) {
    String m = '';
    try {
      final j = jsonDecode(r.body);
      if (j is Map && j['message'] != null) m = ': ${j['message']}';
    } catch (_) {}
    final hint = (r.statusCode == 403 || r.statusCode == 404)
        ? '\nتحقق أن التوكن يشمل مستودع ${Store.acOwner}/${Store.acRepo} بصلاحية Actions (Read and write).'
        : '';
    return 'GitHub ${r.statusCode}$m$hint';
  }

  static dynamic _ok(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) throw GhException(_err(r));
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  static List<Map<String, dynamic>> _list(dynamic v, String key) {
    final l = (v is Map ? v[key] : null);
    if (l is! List) return [];
    return [for (final e in l) if (e is Map) Map<String, dynamic>.from(e)];
  }

  // ── تشغيل ──
  static Future<void> dispatch(String workflowFile, Map<String, String> inputs) async {
    _need();
    final r = await http
        .post(_u('/actions/workflows/$workflowFile/dispatches'),
            headers: {..._h(), 'Content-Type': 'application/json'},
            body: jsonEncode({'ref': Store.acBranch, if (inputs.isNotEmpty) 'inputs': inputs}))
        .timeout(_timeout);
    if (r.statusCode != 204) throw GhException(_err(r));
  }

  // ── متابعة ──
  /// تشغيلات workflow محدد (مثل import-game.yml).
  static Future<List<Map<String, dynamic>>> runs(String workflowFile, {int n = 20, int page = 1}) async {
    _need();
    final r = await http
        .get(_u('/actions/workflows/$workflowFile/runs', {'per_page': '$n', 'page': '$page'}), headers: _h())
        .timeout(_timeout);
    return _list(_ok(r), 'workflow_runs');
  }

  static Future<Map<String, dynamic>> run(int runId) async {
    final r = await http.get(_u('/actions/runs/$runId'), headers: _h()).timeout(_timeout);
    return Map<String, dynamic>.from(_ok(r) as Map);
  }

  static Future<List<Map<String, dynamic>>> jobs(int runId) async {
    final r = await http.get(_u('/actions/runs/$runId/jobs'), headers: _h()).timeout(_timeout);
    return _list(_ok(r), 'jobs');
  }

  /// ملاحظات الـ job: failure (أخطاء) وwarning (تحذيرات) وnotice (تقرير التعديلات).
  static Future<List<Map<String, String>>> annotations(int jobId) async {
    final r = await http.get(_u('/check-runs/$jobId/annotations'), headers: _h()).timeout(_timeout);
    final j = _ok(r);
    if (j is! List) return [];
    final out = <Map<String, String>>[];
    for (final a in j) {
      if (a is! Map) continue;
      final msg = (a['message'] ?? '').toString();
      if (msg.contains('Node.js') && msg.contains('deprecated')) continue; // ضجيج GitHub
      out.add({
        'level': (a['annotation_level'] ?? '').toString(),
        'title': (a['title'] ?? '').toString(),
        'message': msg,
      });
    }
    return out;
  }

  static Future<List<Map<String, dynamic>>> artifacts(int runId) async {
    final r = await http.get(_u('/actions/runs/$runId/artifacts'), headers: _h()).timeout(_timeout);
    return _list(_ok(r), 'artifacts');
  }

  // ── إجراءات ──
  static Future<void> cancel(int runId) async {
    final r = await http.post(_u('/actions/runs/$runId/cancel'), headers: _h()).timeout(_timeout);
    _ok(r);
  }

  static Future<void> rerun(int runId) async {
    final r = await http.post(_u('/actions/runs/$runId/rerun'), headers: _h()).timeout(_timeout);
    _ok(r);
  }

  static Future<void> rerunFailed(int runId) async {
    final r = await http.post(_u('/actions/runs/$runId/rerun-failed-jobs'), headers: _h()).timeout(_timeout);
    _ok(r);
  }

  static Future<String> test() async {
    _need();
    final r = await http.get(_u('/actions/workflows'), headers: _h()).timeout(_timeout);
    final w = _list(_ok(r), 'workflows');
    final names = w.map((e) => e['name']).join('، ');
    return 'متصل ✓  ${Store.acOwner}/${Store.acRepo}\nWorkflows: ${names.isEmpty ? 'لا يوجد' : names}';
  }
}
