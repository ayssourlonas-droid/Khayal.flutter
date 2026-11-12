import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' show AdWidget;

import 'ads_manager.dart';
import 'app_state.dart';
import 'colors.dart';
import 'data_repository.dart';
import 'design.dart';
import 'favorites.dart';
import 'game_card.dart';
import 'home_feed.dart';
import 'glow_button.dart';
import 'nav.dart';
import 'net_loader.dart';
import 'pull_refresh.dart';
import 'audio_player_screen.dart';
import 'details_screen.dart';
import 'settings_screen.dart';
import 'update_check.dart';

/// تطبيع نص عربي/لاتيني للبحث: أحرف صغيرة، بلا تشكيل ولا تطويل، وتوحيد أ إ آ ← ا و ة ← ه و ى ← ي.
String _normSearch(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[\u064B-\u0652\u0640]'), '')
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي');

double _numOf(dynamic v) => double.tryParse('${v ?? ''}') ?? 0;

/// يقابل HomeScreen.gd + MovieLoader.gd + WatchingRow.gd.
/// صفحتان فعليتان: الرئيسية (صف "تابع") والشبكة (كل الألعاب)، انزلاق 0.4 ث (sine/out).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, UpdateCheckMixin {
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

  // البحث والتصفية
  final _searchCtl = TextEditingController();
  String _query = '';
  String _tagFilter = ''; // '' = الكل
  String _sort = 'default'; // default | rating | newest

  List<String> _tagsOf(Map<String, dynamic> g) =>
      g['category_tags'] is List ? (g['category_tags'] as List).map((e) => e.toString()).toList() : <String>[];

  List<Map<String, dynamic>> get _filtered {
    final q = _normSearch(_query.trim());
    final l = _games.where((g) {
      final tags = _tagsOf(g);
      if (_tagFilter.isNotEmpty && !tags.contains(_tagFilter)) return false;
      if (q.isEmpty) return true;
      final m = g['main_scene'] is Map ? g['main_scene'] as Map : const {};
      return _normSearch('${m['title_ar'] ?? ''} ${m['title_en'] ?? ''} ${tags.join(' ')}').contains(q);
    }).toList();
    if (_sort == 'rating') {
      double r(Map<String, dynamic> g) => _numOf(g['main_scene'] is Map ? (g['main_scene'] as Map)['app_rating'] : 0);
      l.sort((a, b) => r(b).compareTo(r(a)));
    } else if (_sort == 'newest') {
      l.sort((a, b) => _numOf(b['release_year']).compareTo(_numOf(a['release_year'])));
    }
    return l;
  }

  bool get _filterActive => _tagFilter.isNotEmpty || _sort != 'default';

  Future<void> _openFilter() async {
    final counts = <String, int>{};
    for (final g in _games) {
      for (final t in _tagsOf(g)) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final tags = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    void apply(VoidCallback f) {
      setState(() {
        f();
        _shown = _batch;
      });
      if (_gridScroll.hasClients) _gridScroll.jumpTo(0);
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14091F),
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('الترتيب', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in const {'default': 'الافتراضي', 'rating': 'الأعلى تقييماً', 'newest': 'الأحدث'}.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _sort == e.key,
                      onSelected: (_) {
                        apply(() => _sort = e.key);
                        Navigator.pop(c);
                      },
                    ),
                ]),
                const SizedBox(height: 16),
                const Text('التصنيف', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoiceChip(
                    label: const Text('الكل'),
                    selected: _tagFilter.isEmpty,
                    onSelected: (_) {
                      apply(() => _tagFilter = '');
                      Navigator.pop(c);
                    },
                  ),
                  for (final t in tags)
                    ChoiceChip(
                      label: Text('$t (${counts[t]})'),
                      selected: _tagFilter == t,
                      onSelected: (_) {
                        apply(() => _tagFilter = t);
                        Navigator.pop(c);
                      },
                    ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
      showDevNotice();
      checkForUpdate();
    });
    _homeScroll.addListener(() => AppState.pageScrollPositions[0] = _homeScroll.offset);
    _gridScroll.addListener(() => AppState.pageScrollPositions[1] = _gridScroll.offset);
  }

  @override
  void dispose() {
    _slide.dispose();
    _homeScroll.dispose();
    _gridScroll.dispose();
    _searchCtl.dispose();
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
    final n = _filtered.length;
    if (_shown < n) setState(() => _shown = (_shown + _batch).clamp(0, n).toInt());
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
    Favorites.instance.setLast((game['id'] ?? '').toString()); // يُحفظ للجلسات القادمة
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
              // الوضع الغامر يخفي شريط الحالة فيمتد المحتوى تحت كاميرا الشاشة؛
              // نترك مساحة سوداء بارتفاع الحافة العلوية (الكاميرا/الشق) فوق البانر.
              final topInset = MediaQuery.of(context).viewPadding.top;
              return Container(
                color: Colors.black,
                width: double.infinity,
                padding: EdgeInsets.only(top: topInset),
                alignment: Alignment.center,
                child: b == null
                    ? const SizedBox.shrink()
                    : SizedBox(
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
              _icon('assets/images/a1u.webp', 170, 100, () => _movePage(0)),
              const SizedBox(width: 20),
              _icon('assets/images/a1y.webp', 170, 100, () => _movePage(1)),
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
              _icon('assets/images/a1w.webp', 170, 100,
                  () => _push(const AudioPlayerScreen(), speed: 3.5)),
            ],
          ),
        ),
        // شريط البحث والتصفية (يظهر في صفحة الألعاب فقط)
        Positioned(
          top: 40,
          left: 170,
          right: 30,
          height: 110,
          child: IgnorePointer(
            ignoring: _page != 1,
            child: AnimatedOpacity(
              opacity: _page == 1 ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(55),
                  border: Border.all(color: AppColors.popupBorder, width: 4),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 52, color: Colors.white70),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchCtl,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(fontSize: 40, color: Colors.white),
                        cursorColor: Colors.white,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'ابحث عن لعبة...',
                          hintStyle: TextStyle(fontSize: 40, color: Colors.white38),
                        ),
                        onChanged: (v) {
                          setState(() {
                            _query = v;
                            _shown = _batch;
                          });
                          if (_gridScroll.hasClients) _gridScroll.jumpTo(0);
                        },
                      ),
                    ),
                    if (_query.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchCtl.clear();
                          setState(() {
                            _query = '';
                            _shown = _batch;
                          });
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.close, size: 48, color: Colors.white70),
                        ),
                      ),
                    GestureDetector(
                      onTap: _openFilter,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(Icons.tune_rounded, size: 56, color: _filterActive ? AppColors.titleRed : Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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

  // صفحة الرئيسية: تابع اللعب ← المفضلة ← لعبة اليوم والاقتراحات
  Widget _homePage() {
    return SizedBox(
      width: 1080,
      child: SingleChildScrollView(
        controller: _homeScroll,
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        child: HomeFeed(
          games: _games,
          fallbackLast: AppState.lastWatchedGame,
          onOpen: _openDetails,
          onTag: (t) {
            // الكلمة المقترحة تفتح صفحة الألعاب مصفّاة بها
            setState(() {
              _tagFilter = t;
              _query = '';
              _searchCtl.clear();
              _shown = _batch;
            });
            if (_gridScroll.hasClients) _gridScroll.jumpTo(0);
            _movePage(1);
          },
        ),
      ),
    );
  }

  // صفحة الشبكة (3 أعمدة)
  Widget _gridPage() {
    final list = _filtered;
    final count = _shown.clamp(0, list.length).toInt();
    if (list.isEmpty && _gotFirstData && _games.isNotEmpty) {
      return const SizedBox(
        width: 1080,
        child: Center(
          child: Text('لا توجد نتائج مطابقة',
              style: TextStyle(fontSize: 52, color: Colors.white70, decoration: TextDecoration.none)),
        ),
      );
    }
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
                  key: ValueKey('g${_gridGen}_${list[i]['id'] ?? i}'),
                  game: list[i],
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
