import 'dart:typed_data';

/// يقابل GlobalState.gd — حالة مشتركة بين الشاشات خلال الجلسة.
class AppState {
  AppState._();

  static Map<String, dynamic> currentGame = {};
  static Uint8List? currentPoster;
  static Uint8List? currentBackground;

  /// ذاكرة مؤقتة للصور: url → bytes
  static final Map<String, Uint8List> imageCache = {};

  /// آخر صفحة وموضع تمرير لكل صفحة
  static int lastPageIndex = 0;
  static final Map<int, double> pageScrollPositions = {};

  /// القوائم المخزّنة بالذاكرة لكل فئة
  static final Map<String, List<Map<String, dynamic>>> cachedLists = {};

  static Map<String, dynamic>? lastWatchedGame;
  static Uint8List? lastPosterBytes;

  static bool devNoticeShown = false;
  static int inputCooldownUntilMs = 0;

  static String supportWhatsappUrl = '';
  static String supportEmail = '';
  static String appPageUrl = '';
  static String feedbackUrl = '';

  static String currentGameUrl = '';

  static bool get inputBlocked =>
      DateTime.now().millisecondsSinceEpoch < inputCooldownUntilMs;
}
