import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'consts.dart';

/// إعدادات محلية على الجهاز فقط. لا تُرفع المفاتيح إلى أي مستودع.
class Store {
  Store._();
  static late SharedPreferences _p;
  static Future<void> init() async => _p = await SharedPreferences.getInstance();

  static String _s(String k, [String d = '']) => _p.getString(k) ?? d;

  static String get ghToken => _s('gh_token');
  static String get ghOwner => _s('gh_owner', defaultOwner);
  static String get ghRepo => _s('gh_repo', defaultRepo);
  static String get ghBranch => _s('gh_branch', defaultBranch);
  static String get clCloud => _s('cl_cloud');
  static String get clKey => _s('cl_key');
  static String get clSecret => _s('cl_secret');

  static Future<void> setAll(Map<String, String> v) async {
    for (final e in v.entries) {
      await _p.setString(e.key, e.value.trim());
    }
  }

  static bool get hasGithub => ghToken.isNotEmpty && ghOwner.isNotEmpty && ghRepo.isNotEmpty;
  static bool get hasCloudinary => clCloud.isNotEmpty && clKey.isNotEmpty && clSecret.isNotEmpty;

  // ── مسودة لعبة جديدة (حفظ تلقائي) ──
  static Map<String, dynamic>? get draft {
    final s = _p.getString('draft_new');
    if (s == null || s.isEmpty) return null;
    try {
      final d = jsonDecode(s);
      return d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveDraft(Map<String, dynamic> d) =>
      _p.setString('draft_new', jsonEncode(d));
  static Future<void> clearDraft() => _p.remove('draft_new');
}
