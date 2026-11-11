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
  // عدّاد فتح الألعاب (يرسل اسم اللعبة فقط، بلا بيانات شخصية)
  static const statsUrl = 'https://khayal-stats1.ayssour-lonas.workers.dev';
  static const useTestAds = false;
  static const testBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const testRewardedId = 'ca-app-pub-3940256099942544/5224354917';
  static const testInterstitialId = 'ca-app-pub-3940256099942544/1033173712';
  static const realBannerId = 'ca-app-pub-2993097916011860/9390159374';
  static const realInterstitialId = 'ca-app-pub-2993097916011860/6997985663';
  /// إعلان واحد عند الدخول إلى لعبة (بعد خصم النقطة).
  static const interstitialOnEnter = true;
  /// أقل فاصل بين إعلانين بيني (ثوانٍ) كي لا يزعج اللاعب.
  static const interstitialMinGapSeconds = 90;
  /// اجعلها true إن كان التطبيق موجهاً للأطفال (قيود Families Policy).
  static const childDirected = false;
  static const realRewardedId = 'ca-app-pub-2993097916011860/1023750041';
  static const rewardPoints = 1;
  /// نقاط مجانية تُمنح مرة واحدة عند أول تشغيل بعد التثبيت.
  static const welcomePoints = 5;
  static const retryBaseSeconds = 15.0;
  static const retryMaxSeconds = 120.0;
}
