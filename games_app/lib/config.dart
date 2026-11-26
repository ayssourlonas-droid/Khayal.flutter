/// يقابل Config.gd — الروابط والمفاتيح الثابتة في مكان واحد.
class Config {
  Config._();

  static const gamesJsonUrl =
      'https://raw.githubusercontent.com/ayssourlonas-droid/khayal.data/refs/heads/main/data_games.json';
  static const gamesAltJsonUrl =
      'https://raw.githubusercontent.com/ayssourlonas-droid/khayal.data/refs/heads/main/data_games_featured.json';
  static const versionCheckUrl =
      'https://raw.githubusercontent.com/ayssourlonas-droid/khayal.data/refs/heads/main/version.json';

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

  /// [أفلام] قائمة الأفلام (تُدار من تطبيق المتحكم). يقرؤها film_data.dart.
  static const filmsJsonUrl =
      'https://raw.githubusercontent.com/ayssourlonas-droid/khayal.data/refs/heads/main/data_films.json';

  // ── مزوّد الإعلانات ──
  /// مزوّد الإعلانات الحالي: 'vast' = إعلان فيديو مباشر (HilltopAds) بلا نقاط (الافتراضي الآن)،
  /// 'levelplay' = Unity LevelPlay، 'admob' = AdMob. كودا LevelPlay وAdMob باقيان للرجوع إليهما عند الحاجة.
  static const adProvider = 'vast';
  static bool get useVast => adProvider == 'vast';
  static bool get useLevelPlay => adProvider == 'levelplay';
  /// نظام النقاط (خصم نقطة لكل لعبة + إعلان المكافأة). false = اللعب مجاني وبلا واجهة نقاط.
  static const pointsEnabled = false;
  // إعلان VAST (HilltopAds، المنطقة 7306841 — رابط نمط IMA)
  static const vastTagUrl =
      'https://windy-imagination.com/dEmfFxzBd.GoNPv/ZyG/Ut/xeJmG9MuoZNU/lck/PmTSc/z-MoD-Y/4/N/DAEstoNCzJMVwrNFj/gs0WNRSnZRsAaRWE1/pvdDDq0rxM';
  /// النطاق المسجّل في HilltopAds لهذه المنطقة (يُستعمل كـ baseUrl لصفحة الإعلان).
  static const vastPageOrigin = 'https://ayssersalhi-a11y.github.io/';
  static const vastStartTimeoutSeconds = 12; // إن لم يبدأ الإعلان خلالها تبدأ اللعبة
  static const vastMaxSeconds = 60; // سقف مدة الإعلان
  // معرّفات LevelPlay (ليست أسراراً: تُضمَّن في التطبيق نفسه)
  static const levelPlayAppKey = '29868e4b5';
  static const lpBannerId = '8ykoywkozkldeeyx';
  static const lpInterstitialId = 'w6mf02zg9u83ppa3';
  static const lpRewardedId = '72xho7pshi2tjthn';

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
  static const interstitialMinGapSeconds = 60;
  /// اجعلها true إن كان التطبيق موجهاً للأطفال (قيود Families Policy).
  static const childDirected = false;
  static const realRewardedId = 'ca-app-pub-2993097916011860/1023750041';
  static const rewardPoints = 1;
  /// نقاط مجانية تُمنح مرة واحدة عند أول تشغيل بعد التثبيت.
  static const welcomePoints = 6;
  /// نقاط مجانية تُضاف مرة واحدة كل يوم (عند أول فتح للتطبيق في ذلك اليوم).
  static const dailyPoints = 2;
  /// سقف الرصيد للنقاط اليومية: لا تُضاف إن بلغ الرصيد هذا الحد (ولا تتجاوزه). نقاط مشاهدة الإعلانات غير مقيّدة بهذا السقف.
  static const dailyCap = 10;
  static const retryBaseSeconds = 15.0;
  static const retryMaxSeconds = 120.0;
}
