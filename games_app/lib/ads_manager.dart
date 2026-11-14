import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'config.dart';
import 'levelplay_ads.dart';
import 'player_points.dart';

/// يقابل AdsManager.gd — AdMob الرسمي (موافقة UMP ثم تهيئة ثم بانر + إعلان مكافأة).
/// المكافأة: نقطة واحدة لكل إعلان يُكمَل مشاهدته.
class AdsManager extends ChangeNotifier {
  AdsManager._();
  static final AdsManager instance = AdsManager._();

  bool _sdkReady = false;
  LevelPlayBackend? _lp;
  bool _bannerWanted = false;
  BannerAd? _banner;
  bool _bannerLoaded = false;
  InterstitialAd? _interstitial;
  bool _loadingInterstitial = false;
  DateTime _lastInterstitial = DateTime.fromMillisecondsSinceEpoch(0);
  RewardedAd? _rewarded;
  bool _loadingRewarded = false;
  double _retrySeconds = Config.retryBaseSeconds;
  bool _rewardGranted = false;

  final _rewardEarned = StreamController<void>.broadcast();
  final _rewardedClosed = StreamController<bool>.broadcast();
  final _rewardedUnavailable = StreamController<void>.broadcast();
  Stream<void> get onRewardEarned => _rewardEarned.stream;
  Stream<bool> get onRewardedClosed => _rewardedClosed.stream;
  Stream<void> get onRewardedUnavailable => _rewardedUnavailable.stream;

  BannerAd? get banner => _bannerLoaded ? _banner : null;
  bool get isRewardedReady => Config.useLevelPlay ? (_lp?.rewardedReady ?? false) : _rewarded != null;

  bool get levelPlayReady => _lp?.initialized ?? false;

  /// ودجت البانر العلوي للشاشة الرئيسية (أو null إن لم يكن هناك إعلان). يخفي الفرق بين المزوّدين.
  Widget? topBannerWidget() {
    if (Config.useLevelPlay) {
      if (!_bannerWanted || !(_lp?.initialized ?? false)) return null;
      return const LevelPlayBannerSlot();
    }
    final b = banner;
    if (b == null) return null;
    return SizedBox(width: b.size.width.toDouble(), height: b.size.height.toDouble(), child: AdWidget(ad: b));
  }

  bool get _supported => !kIsWeb && Platform.isAndroid;

  Future<void> init() async {
    if (!_supported) return;
    _requestConsent();
  }

  // ───── الموافقة (UMP) ثم التهيئة ─────
  void _requestConsent() {
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((err) {
            if (err != null) debugPrint('[Ads] نموذج الموافقة: ${err.message}');
            _initSdk();
          });
        } catch (e) {
          debugPrint('[Ads] consent: $e');
          _initSdk();
        }
      },
      (err) {
        debugPrint('[Ads] تحديث الموافقة: ${err.message}');
        _initSdk();
      },
    );
  }

  Future<void> _initSdk() async {
    if (_sdkReady) return;
    _sdkReady = true;
    if (Config.useLevelPlay) {
      _lp = LevelPlayBackend(
        onChanged: notifyListeners,
        onRewarded: _onEarned,
        onRewardedClosed: () {
          _rewardedClosed.add(_rewardGranted);
          notifyListeners();
        },
      );
      await _lp!.init();
      return;
    }
    if (Config.childDirected) {
      await MobileAds.instance.updateRequestConfiguration(RequestConfiguration(
          tagForChildDirectedTreatment: TagForChildDirectedTreatment.yes));
    }
    await MobileAds.instance.initialize(); // مرة واحدة عند الإقلاع
    _loadRewarded();
    _loadInterstitial();
    if (_bannerWanted) _createBanner();
  }

  String _unit(String testId, String realId) {
    if (!_supported) return '';
    if (Config.useTestAds) return testId;
    if (realId.isEmpty) debugPrint('[Ads] useTestAds=false لكن المعرّف الحقيقي فارغ');
    return realId;
  }

  // ───── البانر ─────
  void showTopBanner() {
    final changed = !_bannerWanted;
    _bannerWanted = true;
    if (Config.useLevelPlay) {
      if (changed) scheduleMicrotask(notifyListeners); // البانر نفسه ودجت يحمّل نفسه
      return;
    }
    if (_sdkReady && _banner == null) _createBanner();
  }

  /// عند فتح لعبة: لا إعلان فوق مساحة اللعب (سياسة AdMob).
  void hideBanner() {
    _bannerWanted = false;
    _banner?.dispose();
    _banner = null;
    _bannerLoaded = false;
    notifyListeners();
  }

  void _createBanner() {
    final unit = _unit(Config.testBannerId, Config.realBannerId);
    if (unit.isEmpty) return;
    _banner = BannerAd(
      adUnitId: unit,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          _bannerLoaded = true;
          notifyListeners();
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('[Ads] فشل البانر: ${err.message}');
          ad.dispose();
          _banner = null;
          _bannerLoaded = false;
          notifyListeners();
        },
      ),
    )..load();
  }

  /// بانر مستقل لشاشة أخرى (إعلان البانر الرئيسي لا يُعرض إلا في ودجت واحد في الوقت نفسه).
  /// يرجع null إن لم تكن الإعلانات جاهزة؛ المستدعي يتخلّص منه بـ dispose().
  BannerAd? createExtraBanner({required VoidCallback onLoaded}) {
    if (!_sdkReady || Config.useLevelPlay) return null;
    final unit = _unit(Config.testBannerId, Config.realBannerId);
    if (unit.isEmpty) return null;
    return BannerAd(
      adUnitId: unit,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => onLoaded(),
        onAdFailedToLoad: (ad, err) {
          debugPrint('[Ads] فشل بانر الإعدادات: ${err.message}');
          ad.dispose();
        },
      ),
    )..load();
  }

  // ───── إعلان بيني عند دخول لعبة ─────
  void _loadInterstitial() {
    if (!_sdkReady || _loadingInterstitial || _interstitial != null || !Config.interstitialOnEnter) return;
    final unit = _unit(Config.testInterstitialId, Config.realInterstitialId);
    if (unit.isEmpty) return;
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: unit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (err) async {
          _loadingInterstitial = false;
          debugPrint('[Ads] فشل تحميل البيني: ${err.message}');
          await Future.delayed(Duration(milliseconds: (_retrySeconds * 1000).round()));
          _loadInterstitial();
        },
      ),
    );
  }

  /// يعرض إعلاناً بينياً إن كان جاهزاً ومضى الفاصل، ثم ينفّذ [proceed] دائماً (مرة واحدة).
  /// لا ينتظر اللاعب أبداً إن لم يكن الإعلان جاهزاً.
  void showInterstitialThen(void Function() proceed) {
    if (Config.useLevelPlay) {
      final lp = _lp;
      if (lp == null) {
        proceed();
      } else {
        lp.showInterstitialThen(proceed);
      }
      return;
    }
    final ad = _interstitial;
    final gap = DateTime.now().difference(_lastInterstitial).inSeconds;
    if (!Config.interstitialOnEnter || ad == null || gap < Config.interstitialMinGapSeconds) {
      _loadInterstitial();
      proceed();
      return;
    }
    _interstitial = null;
    var done = false;
    void go() {
      if (done) return;
      done = true;
      ad.dispose();
      _loadInterstitial();
      proceed();
    }
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) => go(),
      onAdFailedToShowFullScreenContent: (_, err) {
        debugPrint('[Ads] فشل عرض البيني: ${err.message}');
        go();
      },
    );
    _lastInterstitial = DateTime.now();
    ad.show();
  }

  // ───── إعلان المكافأة ─────
  /// يرجع false (ويطلق onRewardedUnavailable) إن لم يكن جاهزاً.
  bool showRewarded() {
    if (Config.useLevelPlay) {
      final lp = _lp;
      if (lp == null || !lp.rewardedReady) {
        _rewardedUnavailable.add(null);
        return false;
      }
      _rewardGranted = false;
      return lp.showRewarded();
    }
    final ad = _rewarded;
    if (ad == null) {
      _rewardedUnavailable.add(null);
      _loadRewarded();
      return false;
    }
    _rewardGranted = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) => _onDismissed(a),
      onAdFailedToShowFullScreenContent: (a, err) {
        debugPrint('[Ads] فشل عرض الإعلان: ${err.message}');
        _onDismissed(a);
      },
    );
    ad.show(onUserEarnedReward: (_, __) => _onEarned());
    return true;
  }

  /// اسم قديم يستدعيه زر AdBtn في الصفحة الرئيسية.
  bool showFullVideo() => showRewarded();

  void _loadRewarded() {
    if (!_sdkReady || _loadingRewarded || _rewarded != null) return;
    final unit = _unit(Config.testRewardedId, Config.realRewardedId);
    if (unit.isEmpty) return;
    _loadingRewarded = true;
    RewardedAd.load(
      adUnitId: unit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingRewarded = false;
          _retrySeconds = Config.retryBaseSeconds;
          _rewarded = ad;
          notifyListeners();
        },
        onAdFailedToLoad: (err) async {
          _loadingRewarded = false;
          debugPrint('[Ads] فشل تحميل المكافأة: ${err.message}');
          // إعادة المحاولة بفاصل متزايد
          await Future.delayed(Duration(milliseconds: (_retrySeconds * 1000).round()));
          _retrySeconds = (_retrySeconds * 2).clamp(0, Config.retryMaxSeconds).toDouble();
          _loadRewarded();
        },
      ),
    );
  }

  void _onEarned() {
    if (_rewardGranted) return;
    _rewardGranted = true;
    PlayerPoints.instance.addPoints(Config.rewardPoints);
    _rewardEarned.add(null);
  }

  void _onDismissed(RewardedAd ad) {
    ad.dispose(); // الإعلان يُستهلك بعد عرضه
    if (identical(_rewarded, ad)) _rewarded = null;
    notifyListeners();
    _rewardedClosed.add(_rewardGranted);
    _loadRewarded();
  }
}
