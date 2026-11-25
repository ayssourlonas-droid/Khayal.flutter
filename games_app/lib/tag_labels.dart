/// تسميات عربية للتصنيفات. المفتاح يبقى إنجليزياً (للتصفية والعدّ)، ويُعرض النص العربي إن وُجد في حقل tags_ar للعبة.
class TagLabels {
  TagLabels._();
  static final Map<String, String> _ar = {};

  /// يلتقط tags_ar من بيانات لعبة: {تصنيف: تسمية}.
  static void absorb(Map<String, dynamic> game) {
    final m = game['tags_ar'];
    if (m is Map) {
      m.forEach((k, v) {
        final key = k.toString();
        final val = v.toString().trim();
        if (val.isNotEmpty) _ar[key] = val;
      });
    }
  }

  static String of(String tag) => _ar[tag] ?? tag;
}
