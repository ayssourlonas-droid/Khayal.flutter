import 'film_consts.dart';

/// نتيجة كشف الرخصة من نص أو رابط.
class LicenseDetection {
  final String? id; // مطابق لـ allowedFilmLicenses إن كانت مسموحة، وإلا null
  final String family; // CC0 | PD | CC-BY | CC-BY-SA | CC-BY-NC | CC-BY-ND | CC-BY-NC-SA | CC-BY-NC-ND | unknown
  final String version;
  final double confidence; // 0..1
  final String evidence;
  final String reason; // سبب الرفض إن لم تكن مسموحة

  const LicenseDetection({
    required this.id,
    required this.family,
    this.version = '',
    required this.confidence,
    this.evidence = '',
    this.reason = '',
  });

  bool get allowed => id != null;

  static const unknown = LicenseDetection(id: null, family: 'unknown', confidence: 0, reason: 'لم أجد رخصة واضحة في النص.');
}

/// كاشف رخص قوي: يقرأ رابط الرخصة أو نصها (عربي/إنجليزي) ويحدد العائلة والإصدار، ويرفض NC وND والنسخ القديمة.
class LicenseDetector {
  LicenseDetector._();

  static final _ccUrl = RegExp(r'creativecommons\.org/licenses/(by(?:-nc)?(?:-sa|-nd)?)/(\d\.\d)', caseSensitive: false);
  static final _zeroUrl = RegExp(r'creativecommons\.org/publicdomain/zero', caseSensitive: false);
  static final _pdmUrl = RegExp(r'creativecommons\.org/publicdomain/mark', caseSensitive: false);
  static final _version = RegExp(r'(?<![\d.])([1-4]\.[05])(?![\d])');

  static bool _has(String t, List<String> words) => words.any(t.contains);

  static LicenseDetection detect(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return LicenseDetection.unknown;
    final low = text.toLowerCase();

    // 1) رابط رخصة صريح (أعلى ثقة)
    final z = _zeroUrl.firstMatch(low);
    if (z != null) return const LicenseDetection(id: 'CC0-1.0', family: 'CC0', confidence: 1, evidence: 'رابط CC0');
    if (_pdmUrl.hasMatch(low)) {
      return const LicenseDetection(id: 'PUBLIC-DOMAIN', family: 'PD', confidence: 1, evidence: 'رابط Public Domain Mark');
    }
    final u = _ccUrl.firstMatch(low);
    if (u != null) {
      return _fromFamily('CC-${u.group(1)!.toUpperCase()}', u.group(2)!, 1.0, 'رابط ${u.group(0)}');
    }

    // 2) نص حر
    final norm = low.replaceAll(RegExp(r'[_\-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ');
    if (RegExp(r'\bcc0\b|cc zero|cc 0\b|creative commons zero').hasMatch(norm) || _has(norm, ['تنازل كامل'])) {
      return const LicenseDetection(id: 'CC0-1.0', family: 'CC0', confidence: 0.9, evidence: 'نص CC0');
    }
    final isCc = _has(norm, ['creative commons', 'المشاع الإبداعي', 'المشاع الابداعي']) || RegExp(r'\bcc by\b').hasMatch(norm);
    if (isCc) {
      final nc = RegExp(r'non ?commercial|\bnc\b|غير تجاري').hasMatch(norm);
      final nd = RegExp(r'no ?deriv|\bnd\b|بدون اشتقاق|بلا اشتقاق').hasMatch(norm);
      final sa = RegExp(r'share ?alike|\bsa\b|المشاركة بالمثل').hasMatch(norm);
      final by = RegExp(r'attribution|\bby\b|نسب').hasMatch(norm);
      if (by || nc || nd || sa) {
        final fam = 'CC-BY${nc ? '-NC' : ''}${nd ? '-ND' : ''}${sa ? '-SA' : ''}';
        final v = _version.firstMatch(norm)?.group(1) ?? '';
        return _fromFamily(fam, v, v.isEmpty ? 0.6 : 0.85, 'نص: ${text.length > 60 ? text.substring(0, 60) : text}');
      }
    }
    if (RegExp(r'public domain|publicdomain|\bpdm\b').hasMatch(norm) || _has(norm, ['الملكية العامة', 'ملك عام', 'مشاع عام'])) {
      return const LicenseDetection(id: 'PUBLIC-DOMAIN', family: 'PD', confidence: 0.75, evidence: 'نص ملك عام');
    }
    return LicenseDetection.unknown;
  }

  static LicenseDetection _fromFamily(String family, String version, double conf, String evidence) {
    final nc = family.contains('NC'), nd = family.contains('ND');
    if (nc || nd) {
      return LicenseDetection(
          id: null,
          family: family,
          version: version,
          confidence: conf,
          evidence: evidence,
          reason: _reject(family, version));
    }
    if (version.isEmpty) {
      // بلا إصدار: لا نخمّن؛ نقترح 4.0 بثقة منخفضة ويؤكدها المستخدم
      final guess = '$family-4.0';
      return LicenseDetection(
          id: allowedFilmLicenses.contains(guess) ? guess : null,
          family: family,
          version: '4.0؟',
          confidence: 0.5,
          evidence: evidence,
          reason: 'الإصدار غير مذكور: افتراض 4.0 غير مؤكد، تحقق من صفحة المصدر.');
    }
    final id = '$family-$version';
    if (allowedFilmLicenses.contains(id)) {
      return LicenseDetection(id: id, family: family, version: version, confidence: conf, evidence: evidence);
    }
    return LicenseDetection(
        id: null, family: family, version: version, confidence: conf, evidence: evidence, reason: _reject(family, version));
  }

  static String _reject(String family, String version) {
    if (family.contains('NC')) return 'غير تجارية (NC): خيال يعرض إعلانات فهو استعمال تجاري.';
    if (family.contains('ND')) return 'بلا اشتقاق (ND): لا يجوز قص العمل أو دبلجته أو تعديله.';
    return 'نسخة قديمة ($version) من الرخصة: افحصها يدوياً ثم اختر الرخصة المقابلة.';
  }
}
