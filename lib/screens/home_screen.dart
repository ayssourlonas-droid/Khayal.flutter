import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/ads_manager.dart';
import '../core/app_state.dart';
import '../core/colors.dart';
import '../core/config.dart';
import '../core/data_repository.dart';
import '../widgets/alert_popup.dart';
import '../widgets/design.dart';
import '../widgets/game_card.dart';
import '../widgets/glow_button.dart';
import '../widgets/nav.dart';
import '../widgets/net_loader.dart';
import '../widgets/pull_refresh.dart';
import 'audio_player_screen.dart';
import 'details_screen.dart';
import 'settings_screen.dart';

/// يقابل HomeScreen.gd + MovieLoader.gd + WatchingRow.gd.
/// صفحتان فعليتان: الرئيسية (صف "تابع") والشبكة (كل الألعاب)، انزلاق 0.4 ث (sine/out).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  static const _batch = 20;

  late final AnimationController _slide =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  late Animation<double> _slideAnim;
  int _page = 0; // 0 = الرئيسية، 1 = الشبكة
  double _fromIdx = 0;

  final _homeScroll = ScrollController();
  final _gridScroll = ScrollController();

  String _category = 'movie';
  List<Map<String, dynamic>> _games = [];
  int _shown = _batch;
  bool _gotFirstData = false;
  int _gridGen = 0; // يُزاد عند التحديث لإعادة بناء البطاقات

  @override
  void initState() {
    super.initState();
    _page = AppState.lastPageIndex.clamp(0, 1).toInt();
    _fromIdx = _page.toDouble();
    _slideAnim = AlwaysStoppedAnimation(_fromIdx);
    AdsManager.instance.showTopBanner();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScroll();
      _showDevNotice();
      _checkForUpdate();
    });
    _homeScroll.addListener(() => AppState.pageScrollPositions[0] = _homeScroll.offset);
    _gridScroll.addListener(() => AppState.pageScrollPositions[1] = _gridScroll.offset);
  }

  @override
  void dispose() {
    _slide.dispose();
    _homeScroll.dispose();
    _gridScroll.dispose();
    super.dispose();
  }

  void _restoreScroll() {
    for (final e in {0: _homeScroll, 1: _gridScroll}.entries) {
      final pos = AppState.pageScrollPositions[e.key];
      if (pos != null && e.value.hasClients) {
        e.value.jumpTo(pos.clamp(0.0, e.value.position.maxScrollExtent));
      }
    }
  }

  // ───────── البيانات (ذاكرة ← قرص ← شبكة) ─────────
  Future<void> _loadData({bool force = false}) async {
    await DataRepository.load(
      _category,
      (games, {required fromNetwork}) {
        if (!mounted) return;
        setState(() {
          _games = games;
          _gotFirstData = true;
          if (_shown < _batch) _shown = _batch;
        });
      },
      forceNetwork: force,
    );
    if (mounted && !_gotFirstData) {
      // لا بيانات من أي مصدر: نوقف المؤشر أيضاً ليظهر فراغ بدل دوران أبدي
      setState(() => _gotFirstData = true);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _games = [];
      _shown = _batch;
      _gotFirstData = false;
      _gridGen++;
    });
    await Future.delayed(const Duration(milliseconds: 300));
    await _loadData(force: true);
  }

  /// يقابل switch_category في MovieLoader (القائمة الثانية).
  void switchCategory(String c) {
    if (c == _category) return;
    setState(() {
      _category = c;
      _games = [];
      _shown = _batch;
      _gotFirstData = false;
      _gridGen++;
    });
    _loadData();
  }

  void _loadMore() {
    if (_shown < _games.length) setState(() => _shown = (_shown + _batch).clamp(0, _games.length).toInt());
  }

  // ───────── التنقل بين الصفحتين ─────────
  void _movePage(int idx) {
    if (idx == _page) return;
    _fromIdx = _slideAnim.value;
    _slideAnim = Tween<double>(begin: _fromIdx, end: idx.toDouble())
        .animate(CurvedAnimation(parent: _slide, curve: Curves.easeOutSine));
    _slide.forward(from: 0);
    setState(() {
      _page = idx;
      AppState.lastPageIndex = idx;
    });
  }

  // ───────── فتح التفاصيل ─────────
  void _openDetails(Map<String, dynamic> game, Uint8List? poster) {
    AppState.currentGame = game;
    AppState.lastWatchedGame = game;
    AppState.currentPoster = poster;
    AppState.lastPosterBytes = poster;
    final bg = (game['details_scene'] is Map ? game['details_scene']['background_url'] : null) ?? '';
    AppState.currentBackground = ImageStore.peek(bg.toString());
    if (AppState.currentBackground == null && bg.toString().startsWith('http')) {
      ImageStore.get(bg.toString()); // تحميل مسبق للخلفية
    }
    _push(const DetailsScreen());
  }

  /// بعد العودة لهذه الشاشة يعود البانر (أُخفي أثناء اللعب) وتُحدَّث البطاقات.
  void _push(Widget page, {double speed = 1}) {
    Nav.push(page, speed: speed).then((_) {
      AdsManager.instance.showTopBanner();
      if (mounted) setState(() {});
    });
  }

  // ───────── نافذة "قيد التطوير" (مرة واحدة لكل تشغيل) ─────────
  Future<void> _showDevNotice() async {
    if (AppState.devNoticeShown) return;
    AppState.devNoticeShown = true;
    _devOpen = true;
    await showAlertPopup(
      context,
      title: 'تنبيه !',
      message: 'يرجى العلم أن التطبيق ما زال قيد التطوير،\nوقد تواجهكم بعض المشكلات.\nنرجو منكم التفهم.❤️',
      buttons: const [PopupBtn(' موافق ', 2)],
    );
    _devOpen = false;
  }

  /// تُغلق نافذة "قيد التطوير" إن كانت ظاهرة قبل رسائل التحديث (لا تتراكم النوافذ).
  void _hideDevNotice() {
    if (_devOpen && mounted) {
      _devOpen = false;
      Navigator.of(context).pop(0);
    }
  }

  // ───────── فحص التحديث ─────────
  bool _dialogOpen = false;
  bool _devOpen = false;

  Future<void> _checkForUpdate() async {
    http.Response res;
    try {
      res = await http
          .get(Uri.parse('${Config.versionCheckUrl}?t=${DateTime.now().millisecondsSinceEpoch ~/ 1000}'))
          .timeout(const Duration(seconds: 15));
    } on SocketException {
      return; // لا إنترنت: تجاهل صامت
    } on TimeoutException {
      return;
    } on HandshakeException {
      return;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (res.statusCode != 200) return _showCheckFailed();
    dynamic parsed;
    try {
      parsed = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return _showCheckFailed();
    }
    if (parsed is! Map) return _showCheckFailed();

    String s(String k) => (parsed[k] ?? '').toString().trim();
    final remote = s('latest_version');
    final url = s('download_url');
    final mode = parsed['update_mode'] == null ? 'optional' : s('update_mode');

    AppState.supportWhatsappUrl = s('whatsapp_url');
    AppState.supportEmail = s('support_email');
    AppState.appPageUrl = s('app_page_url');
    AppState.feedbackUrl = s('feedback_url');

    if (remote.isEmpty || url.isEmpty) return _showCheckFailed();

    final local = (await PackageInfo.fromPlatform()).version;
    if (_isNewer(remote, local)) _showUpdate(url, mode == 'forced');
  }

  /// مقارنة رقمية x.y.z (وليست نصية).
  bool _isNewer(String remote, String local) {
    final r = remote.split('.'), l = local.split('.');
    final n = r.length > l.length ? r.length : l.length;
    for (var i = 0; i < n; i++) {
      final a = i < r.length ? int.tryParse(r[i]) ?? 0 : 0;
      final b = i < l.length ? int.tryParse(l[i]) ?? 0 : 0;
      if (a > b) return true;
      if (a < b) return false;
    }
    return false;
  }

  Future<void> _showCheckFailed() async {
    if (_dialogOpen || !mounted) return;
    _dialogOpen = true;
    _hideDevNotice();
    await showAlertPopup(
      context,
      title: '⚠️ تعثّر فحص الإصدار',
      message: 'تعثّر فحص إصدار التطبيق.\nيرجى ترقية التطبيق إلى آخر إصدار.',
      buttons: const [PopupBtn(' موافق ', 2), PopupBtn(' تجاوز ', 3)],
    );
    _dialogOpen = false;
  }

  Future<void> _showUpdate(String url, bool forced) async {
    if (_dialogOpen || !mounted) return;
    _dialogOpen = true;
    _hideDevNotice();
    final msg = forced
        ? 'يوجد إصدار جديد إلزامي من التطبيق.\nيجب التحديث للمتابعة.'
        : 'يتوفر إصدار جديد من التطبيق.\nيُنصح بالتحديث للحصول على أحدث الميزات والإصلاحات.';
    while (mounted) {
      final r = await showAlertPopup(
        context,
        title: '🔄 يتوفر تحديث',
        message: msg,
        buttons: [const PopupBtn(' تحديث ⬆️ ', 2), if (!forced) const PopupBtn(' تجاوز ', 1)],
      );
      if (r == 0) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        if (!forced) break;
        await Future.delayed(const Duration(milliseconds: 250)); // الإجباري: تعاد النافذة
      } else {
        break;
      }
    }
    _dialogOpen = false;
  }

  // ───────── البناء ─────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ListenableBuilder(
            listenable: AdsManager.instance,
            builder: (_, __) {
              final b = AdsManager.instance.banner;
              if (b == null) return const SizedBox.shrink();
              return Container(
                color: Colors.black,
                width: double.infinity,
                height: b.size.height.toDouble(),
                alignment: Alignment.center,
                child: SizedBox(
                  width: b.size.width.toDouble(),
                  height: b.size.height.toDouble(),
                  child: AdWidget(ad: b),
                ),
              );
            },
          ),
          Expanded(
            child: GodotGradientBox(
              homeGradient,
              child: Design(builder: (context, h) => _content(h)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(double h) {
    const topMargin = 200.0, bottomMargin = 270.0;
    return Stack(
      children: [
        // الصفحات
        Positioned(
          top: topMargin,
          bottom: bottomMargin,
          left: 0,
          right: 0,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _slide,
              builder: (_, __) {
                final idx = _slide.isAnimating || _slide.isCompleted ? _slideAnim.value : _page.toDouble();
                return Stack(
                  children: [
                    Transform.translate(offset: Offset(idx * 1080, 0), child: _homePage()),
                    Transform.translate(offset: Offset((idx - 1) * 1080, 0), child: _gridPage()),
                  ],
                );
              },
            ),
          ),
        ),
        // مؤشر تحميل الصفحة
        Positioned(
          top: topMargin,
          bottom: bottomMargin,
          left: 0,
          right: 0,
          child: Center(
            child: NetLoader(width: 220, height: 220, loading: !_gotFirstData && _page == 1),
          ),
        ),
        // شريط التنقل السفلي (أيقونتان ظاهرتان: الرئيسية، الألعاب)
        Positioned(
          bottom: 160,
          left: 0,
          right: 0,
          height: 100,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            textDirection: TextDirection.rtl,
            children: [
              _icon('assets/images/m1_a1f.webp', 170, 100, () => _movePage(0)),
              const SizedBox(width: 20),
              _icon('assets/images/m1_a1j.webp', 170, 100, () => _movePage(1)),
            ],
          ),
        ),
        // عمود التبويبات يمين الوسط (زر مشغّل الصوت)
        Positioned(
          right: 0,
          top: h / 2 - 210,
          width: 170,
          height: 420,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _icon('assets/images/m1_a1h.webp', 170, 100,
                  () => _push(const AudioPlayerScreen(), speed: 3.5)),
            ],
          ),
        ),
        // الإعدادات أعلى اليسار
        Positioned(
          left: 30,
          top: 30,
          child: _icon('assets/images/a1g.webp', 100, 100,
              () => _push(const SettingsScreen(), speed: 3.5)),
        ),
      ],
    );
  }

  Widget _icon(String asset, double w, double h, VoidCallback onTap) => GlowButton(
        onTap: onTap,
        child: SizedBox(width: w, height: h, child: Image.asset(asset, fit: BoxFit.contain)),
      );

  // صفحة الرئيسية: صف "تابع اللعب"
  Widget _homePage() {
    final g = AppState.lastWatchedGame;
    return SizedBox(
      width: 1080,
      child: SingleChildScrollView(
        controller: _homeScroll,
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        child: g == null
            ? const SizedBox(height: 10)
            : Align(
                alignment: Alignment.topRight,
                child: GameCard(
                  key: ValueKey('last_${g['id']}'),
                  game: g,
                  posterBytes: AppState.lastPosterBytes,
                  onTap: (game, poster) {
                    AppState.currentGame = game;
                    AppState.currentPoster = poster ?? AppState.lastPosterBytes;
                    _push(const DetailsScreen());
                  },
                ),
              ),
      ),
    );
  }

  // صفحة الشبكة (3 أعمدة)
  Widget _gridPage() {
    final count = _shown.clamp(0, _games.length).toInt();
    return SizedBox(
      width: 1080,
      child: PullRefreshScroll(
        controller: _gridScroll,
        onRefresh: _refresh,
        onNearBottom: _loadMore,
        slivers: [
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisExtent: 560, // 520 + هامش 20×2
              childAspectRatio: 1,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => Align(
                alignment: Alignment.topCenter,
                child: GameCard(
                  key: ValueKey('g${_gridGen}_${_games[i]['id'] ?? i}'),
                  game: _games[i],
                  onTap: _openDetails,
                ),
              ),
              childCount: count,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}
