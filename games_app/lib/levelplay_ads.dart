import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';

import 'config.dart';

/// إعلانات Unity LevelPlay (ironSource): تهيئة + مكافأة + بيني.
/// يستدعيه AdsManager حين تكون Config.adProvider = 'levelplay'، ويبقى كود AdMob كما هو للرجوع إليه.
class LevelPlayBackend implements LevelPlayInitListener {
  LevelPlayBackend({
    required this.onChanged,
    required this.onRewarded,
    required this.onRewardedClosed,
  });

  /// تغيّرت الجاهزية (تهيئة أو تحميل مكافأة) فيُحدَّث الواجهة.
  final VoidCallback onChanged;

  /// أكمل اللاعب مشاهدة إعلان المكافأة (قد يصل بعد الإغلاق، لذلك لا نعتمد على الإغلاق).
  final VoidCallback onRewarded;

  /// أُغلق إعلان المكافأة (يُرسَل بعد مهلة قصيرة كي تصل المكافأة إن تأخرت).
  final VoidCallback onRewardedClosed;

  bool initialized = false;
  bool rewardedReady = false;
  bool _interstitialReady = false;

  LevelPlayRewardedAd? _rewarded;
  LevelPlayInterstitialAd? _interstitial;
  double _retrySeconds = Config.retryBaseSeconds;
  int _initTries = 0;
  DateTime _lastInterstitial = DateTime.fromMillisecondsSinceEpoch(0);
  VoidCallback? _pendingProceed;

  // ───── التهيئة ─────
  Future<void> init() async {
    _initTries++;
    try {
      if (Config.childDirected) {
        LevelPlayPrivacySettings.setCOPPA(true);
      }
      final request = LevelPlayInitRequest.builder(Config.levelPlayAppKey).build();
      await LevelPlay.init(initRequest: request, initListener: this);
    } catch (e) {
      debugPrint('[LevelPlay] init: $e');
      _retryInit();
    }
  }

  void _retryInit() {
    if (_initTries >= 4) return;
    Future.delayed(Duration(seconds: 20 * _initTries), () {
      if (!initialized) init();
    });
  }

  @override
  void onInitSuccess(LevelPlayConfiguration configuration) {
    initialized = true;
    _rewarded = LevelPlayRewardedAd(adUnitId: Config.lpRewardedId);
    _rewarded!.setListener(_RewardedListener(this));
    _rewarded!.loadAd();
    if (Config.interstitialOnEnter) {
      _interstitial = LevelPlayInterstitialAd(adUnitId: Config.lpInterstitialId);
      _interstitial!.setListener(_InterstitialListener(this));
      _interstitial!.loadAd();
    }
    onChanged();
  }

  @override
  void onInitFailed(LevelPlayInitError error) {
    debugPrint('[LevelPlay] فشلت التهيئة: $error');
    _retryInit();
  }

  // ───── المكافأة ─────
  /// يرجع false إن لم يكن الإعلان جاهزاً.
  bool showRewarded() {
    final ad = _rewarded;
    if (ad == null || !rewardedReady) return false;
    rewardedReady = false;
    onChanged();
    ad.showAd();
    return true;
  }

  void _rewardedLoaded() {
    rewardedReady = true;
    _retrySeconds = Config.retryBaseSeconds;
    onChanged();
  }

  void _rewardedGone({required bool closed}) {
    rewardedReady = false;
    onChanged();
    if (closed) {
      // onAdRewarded قد يصل بعد onAdClosed، فنؤخّر إعلام الإغلاق قليلاً.
      Future.delayed(const Duration(milliseconds: 400), onRewardedClosed);
    }
    _reloadRewarded(delaySeconds: closed ? 0 : _retrySeconds);
  }

  void _reloadRewarded({double delaySeconds = 0}) {
    Future.delayed(Duration(milliseconds: (delaySeconds * 1000).round()), () {
      _rewarded?.loadAd();
    });
    if (delaySeconds > 0) {
      _retrySeconds = (_retrySeconds * 2).clamp(0, Config.retryMaxSeconds).toDouble();
    }
  }

  // ───── البيني ─────
  void showInterstitialThen(VoidCallback proceed) {
    final ad = _interstitial;
    final gap = DateTime.now().difference(_lastInterstitial).inSeconds;
    if (!Config.interstitialOnEnter || ad == null || !_interstitialReady || gap < Config.interstitialMinGapSeconds) {
      proceed();
      return;
    }
    _interstitialReady = false;
    _pendingProceed = proceed;
    _lastInterstitial = DateTime.now();
    ad.showAd();
  }

  void _interstitialLoaded() => _interstitialReady = true;

  void _interstitialFailedToLoad() {
    _interstitialReady = false;
    Future.delayed(Duration(milliseconds: (_retrySeconds * 1000).round()), () => _interstitial?.loadAd());
  }

  void _interstitialDone() {
    final p = _pendingProceed;
    _pendingProceed = null;
    _interstitial?.loadAd();
    if (p != null) p(); // مرة واحدة فقط
  }
}

class _RewardedListener implements LevelPlayRewardedAdListener {
  _RewardedListener(this.b);
  final LevelPlayBackend b;

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) => b._rewardedLoaded();

  @override
  void onAdLoadFailed(LevelPlayAdError error) {
    debugPrint('[LevelPlay] فشل تحميل المكافأة: $error');
    b._rewardedGone(closed: false);
  }

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdDisplayFailed(LevelPlayAdError error, LevelPlayAdInfo adInfo) {
    debugPrint('[LevelPlay] فشل عرض المكافأة: $error');
    b._rewardedGone(closed: true);
  }

  @override
  void onAdClosed(LevelPlayAdInfo adInfo) => b._rewardedGone(closed: true);

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdInfoChanged(LevelPlayAdInfo adInfo) {}

  @override
  void onAdRewarded(LevelPlayReward reward, LevelPlayAdInfo adInfo) => b.onRewarded();
}

class _InterstitialListener implements LevelPlayInterstitialAdListener {
  _InterstitialListener(this.b);
  final LevelPlayBackend b;

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) => b._interstitialLoaded();

  @override
  void onAdLoadFailed(LevelPlayAdError error) {
    debugPrint('[LevelPlay] فشل تحميل البيني: $error');
    b._interstitialFailedToLoad();
  }

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdDisplayFailed(LevelPlayAdError error, LevelPlayAdInfo adInfo) {
    debugPrint('[LevelPlay] فشل عرض البيني: $error');
    b._interstitialDone();
  }

  @override
  void onAdClosed(LevelPlayAdInfo adInfo) => b._interstitialDone();

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdInfoChanged(LevelPlayAdInfo adInfo) {}
}

/// بانر LevelPlay: يحمّل نفسه ويظهر فقط بعد نجاح التحميل (قبله شريط بارتفاع 1 كي لا يبقى فراغ).
/// كل نسخة منه لها مستمعها الخاص (تتطلبه LevelPlay).
class LevelPlayBannerSlot extends StatefulWidget {
  const LevelPlayBannerSlot({super.key});

  @override
  State<LevelPlayBannerSlot> createState() => _LevelPlayBannerSlotState();
}

class _LevelPlayBannerSlotState extends State<LevelPlayBannerSlot> implements LevelPlayBannerAdViewListener {
  final GlobalKey<LevelPlayBannerAdViewState> _key = GlobalKey<LevelPlayBannerAdViewState>();
  final LevelPlayAdSize _size = LevelPlayAdSize.BANNER;
  bool _loaded = false;
  double _retry = Config.retryBaseSeconds;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _key.currentState?.destroy();
    super.dispose();
  }

  void _scheduleRetry() {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: (_retry * 1000).round()), () {
      _key.currentState?.loadAd();
    });
    _retry = (_retry * 2).clamp(0, Config.retryMaxSeconds).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size.width.toDouble(),
      height: _loaded ? _size.height.toDouble() : 1,
      child: LevelPlayBannerAdView(
        key: _key,
        adUnitId: Config.lpBannerId,
        adSize: _size,
        listener: this,
        onPlatformViewCreated: () => _key.currentState?.loadAd(),
      ),
    );
  }

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) {
    _retry = Config.retryBaseSeconds;
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void onAdLoadFailed(LevelPlayAdError error) {
    debugPrint('[LevelPlay] فشل البانر: $error');
    if (mounted) setState(() => _loaded = false);
    _scheduleRetry();
  }

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdDisplayFailed(LevelPlayAdInfo adInfo, LevelPlayAdError error) {
    debugPrint('[LevelPlay] فشل عرض البانر: $error');
  }

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdExpanded(LevelPlayAdInfo adInfo) {}

  @override
  void onAdCollapsed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdLeftApplication(LevelPlayAdInfo adInfo) {}
}
