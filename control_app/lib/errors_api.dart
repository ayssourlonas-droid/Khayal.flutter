import 'dart:convert';
import 'package:http/http.dart' as http;
import 'github.dart' show GhException;
import 'store.dart';

class ErrModel {
  final String model;
  final String android;
  final int n;
  ErrModel(this.model, this.android, this.n);
}

/// خطأ مجمَّع (الأخطاء المتشابهة تحمل البصمة نفسها).
class AppError {
  final String fp, app, ver, type, msg, stack, ctx, first, last;
  final bool fatal;
  final bool resolved;
  final int n, devices;
  final List<ErrModel> models;
  AppError(this.fp, this.app, this.ver, this.type, this.msg, this.stack, this.ctx, this.first, this.last, this.fatal,
      this.resolved, this.n, this.devices, this.models);

  /// نص جاهز للنسخ وإرساله للمطوّر.
  String report() => [
        '[$app $ver] $type${fatal ? ' (غير ملتقَط)' : ''}',
        msg,
        if (ctx.isNotEmpty) 'اللعبة/السياق: $ctx',
        'المرات: $n | الأجهزة: $devices | أول ظهور: $first | آخر ظهور: $last',
        if (models.isNotEmpty) 'الأجهزة: ${models.map((m) => '${m.model} / Android ${m.android} ×${m.n}').join(' ، ')}',
        '',
        stack,
      ].join('\n');
}

class ErrorsData {
  final int open;
  final List<AppError> errors;
  ErrorsData(this.open, this.errors);
}

int _int(Object? v) => (v is num) ? v.toInt() : 0;
String _s(Object? v) => v == null ? '' : '$v';

/// يقرأ أخطاء تطبيق خيال من Worker الإحصاءات (نفس الرابط والرمز المحفوظين في الإعدادات).
class ErrorsApi {
  ErrorsApi._();

  static String _base() {
    var base = Store.statsUrl.trim();
    if (base.isEmpty || Store.statsToken.isEmpty) {
      throw GhException('أدخل رابط الإحصاء والرمز في الإعدادات أولاً.');
    }
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    return base;
  }

  static void _check(http.Response r) {
    if (r.statusCode == 401) throw GhException('الرمز غير صحيح (401).');
    if (r.statusCode == 501) throw GhException('لم تُربط قاعدة D1 بالـWorker بعد.');
    if (r.statusCode == 404) throw GhException('الـWorker لا يدعم سجل الأخطاء بعد: حدّث كوده وأنشئ جداوله (schema4.sql).');
    if (r.statusCode >= 300) throw GhException('خطأ ${r.statusCode}');
  }

  static Future<ErrorsData> fetch({int days = 30, bool all = false}) async {
    final r = await http
        .get(Uri.parse('${_base()}/errors?days=$days&all=${all ? 1 : 0}'),
            headers: {'Authorization': 'Bearer ${Store.statsToken}'})
        .timeout(const Duration(seconds: 30));
    _check(r);
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final list = (j is Map && j['errors'] is List) ? j['errors'] as List : [];
    final out = <AppError>[];
    for (final e in list) {
      if (e is! Map) continue;
      final ms = <ErrModel>[
        for (final m in (e['models'] is List ? e['models'] as List : []))
          if (m is Map) ErrModel(_s(m['model']), _s(m['android']), _int(m['n']))
      ];
      out.add(AppError(_s(e['fp']), _s(e['app']), _s(e['ver']), _s(e['type']), _s(e['msg']), _s(e['stack']),
          _s(e['ctx']), _s(e['first']), _s(e['last']), _int(e['fatal']) == 1, _int(e['resolved']) == 1, _int(e['n']),
          _int(e['devices']), ms));
    }
    return ErrorsData(j is Map ? _int(j['open']) : out.length, out);
  }

  /// action: resolve | reopen | delete
  static Future<void> act(String fp, String action) async {
    final r = await http
        .post(Uri.parse('${_base()}/errors'),
            headers: {'Authorization': 'Bearer ${Store.statsToken}', 'Content-Type': 'application/json'},
            body: jsonEncode({'fp': fp, 'action': action}))
        .timeout(const Duration(seconds: 20));
    _check(r);
  }
}
