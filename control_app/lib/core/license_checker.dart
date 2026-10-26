import 'dart:convert';
import 'consts.dart';
import 'github.dart';

class LicenseResult {
  final bool allowed;
  final String? spdx;
  final String? developer;
  final String? description;
  final String? homepage;
  final String? title;
  final String message;
  LicenseResult({
    required this.allowed,
    required this.message,
    this.spdx,
    this.developer,
    this.description,
    this.homepage,
    this.title,
  });
}

/// يتعرف على رخصة اللعبة تلقائياً من رابط مستودع GitHub (أو صفحة github.io).
class LicenseChecker {
  LicenseChecker._();

  static const _caveat =
      '\n⚠️ هذا فحص لرخصة الكود فقط. تأكد أن الصور والأصوات والخطوط داخل اللعبة تحت نفس الرخصة.';

  static ({String owner, String repo})? parse(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || u.host.isEmpty) return null;
    final segs = u.pathSegments.where((s) => s.isNotEmpty).toList();
    final host = u.host.toLowerCase();
    if (host == 'github.com' || host == 'www.github.com') {
      if (segs.length < 2) return null;
      return (owner: segs[0], repo: segs[1].replaceAll(RegExp(r'\.git$'), ''));
    }
    if (host.endsWith('.github.io')) {
      final owner = host.split('.').first;
      final repo = segs.isNotEmpty ? segs.first : '$owner.github.io';
      return (owner: owner, repo: repo);
    }
    return null;
  }

  static Future<LicenseResult> check(String url) async {
    final p = parse(url);
    if (p == null) {
      return LicenseResult(
        allowed: false,
        message: 'الرابط ليس مستودع GitHub أو صفحة github.io.\n'
            'اختر الرخصة يدوياً: OWNED (لعبتك أنت) أو PARTNER (اتفاق مكتوب مع صاحبها)، '
            'وضع رابط يثبت ذلك في خانة المصدر.',
      );
    }
    final r = await Github.api('/repos/${p.owner}/${p.repo}');
    if (r.statusCode == 404) {
      return LicenseResult(allowed: false, message: 'المستودع ${p.owner}/${p.repo} غير موجود أو خاص.');
    }
    if (r.statusCode != 200) {
      return LicenseResult(
          allowed: false, message: 'تعذّر الفحص (GitHub ${r.statusCode}). حاول لاحقاً أو أضف Token في الإعدادات.');
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final lic = j['license'];
    final spdx = lic is Map ? lic['spdx_id']?.toString() : null;
    final owner = (j['owner'] is Map ? j['owner']['login'] : p.owner)?.toString();
    final desc = j['description']?.toString();
    final home = j['homepage']?.toString();
    final title = j['name']?.toString();

    if (spdx == null) {
      return LicenseResult(
        allowed: false,
        developer: owner,
        description: desc,
        homepage: home,
        title: title,
        message: '✗ لا توجد رخصة في المستودع = كل الحقوق محفوظة. ممنوع استخدامها بدون إذن مكتوب.',
      );
    }
    if (allowedLicenses.contains(spdx)) {
      return LicenseResult(
        allowed: true,
        spdx: spdx,
        developer: owner,
        description: desc,
        homepage: home,
        title: title,
        message: '✓ الرخصة $spdx مسموحة.$_caveat',
      );
    }
    return LicenseResult(
      allowed: false,
      spdx: spdx,
      developer: owner,
      description: desc,
      homepage: home,
      title: title,
      message: '✗ الرخصة $spdx غير مسموحة في التطبيق (NC/ND/AGPL/LGPL/غير معروفة).',
    );
  }
}
