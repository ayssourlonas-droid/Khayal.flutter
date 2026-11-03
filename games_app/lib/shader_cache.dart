import 'dart:ui' as ui;

/// تحميل برامج الشيدر مرة واحدة. إن فشل التحميل (جهاز لا يدعمه) نرجع null
/// وتعرض الودجات بديلاً بسيطاً بدل أن ينهار التطبيق.
class ShaderCache {
  ShaderCache._();
  static final Map<String, Future<ui.FragmentProgram?>> _cache = {};

  static Future<ui.FragmentProgram?> load(String asset) {
    return _cache.putIfAbsent(asset, () async {
      try {
        return await ui.FragmentProgram.fromAsset(asset);
      } catch (_) {
        return null;
      }
    });
  }
}
