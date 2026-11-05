/// يقابل Config.gd — الروابط والمفاتيح الثابتة في مكان واحد.
class Config {
  Config._();

  static const gamesJsonUrl =
      'https://raw.githubusercontent.com/ayssourlonas-droid/khayal-control/refs/heads/main/data_games.json';
  static const gamesAltJsonUrl =
      'https://raw.githubusercontent.com/ayssourlonas-droid/khayal-control/refs/heads/main/data_games_featured.json';
  static const versionCheckUrl =
      'https://raw.githubusercontent.com/ayssourlonas-droid/khayal-control/refs/heads/main/version.json';

  /// تراخيص مسموح بها لإعادة التوزيع التجاري. NC و ND ممنوعتان عمداً.
  static const allowedLicenses = [
    'MIT',
    'Apache-2.0',
    'BSD-2-Clause',
    'BSD-3-Clause',
    'CC0-1.0',
    'CC-BY-4.0',
    'CC-BY-3.0',
    'GPL-3.0',
    'ISC',
    'Zlib',
    'OWNED',
    'PARTNER',
  ];

  // ── AdMob ──
  /// اجعلها false قبل النشر بعد وضع المعرّفات الحقيقية.
  static const useTestAds = true;
  static const testBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const testRewardedId = 'ca-app-pub-3940256099942544/5224354917';
  static const testInterstitialId = 'ca-app-pub-3940256099942544/1033173712';
  static const realBannerId = '';
  static const realInterstitialId = '';
  /// إعلان واحد عند الدخول إلى لعبة (بعد خصم النقطة).
  static const interstitialOnEnter = true;
  /// أقل فاصل بين إعلانين بيني (ثوانٍ) كي لا يزعج اللاعب.
  static const interstitialMinGapSeconds = 90;
  /// اجعلها true إن كان التطبيق موجهاً للأطفال (قيود Families Policy).
  static const childDirected = false;
  static const realRewardedId = '';
  static const rewardPoints = 1;
  static const retryBaseSeconds = 15.0;
  static const retryMaxSeconds = 120.0;
}
