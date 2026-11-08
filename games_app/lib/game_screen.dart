import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'ads_manager.dart';
import 'app_state.dart';
import 'colors.dart';
import 'game_library.dart';
import 'net_loader.dart';

/// يقابل GameScreen.gd + GameWebView.gd + إضافة KhayalWebView:
/// يشغّل لعبة الويب داخل WebView محصّن (https فقط، بلا جسر JS، تنقّل داخل نفس الموقع،
/// لا تجاوز لأخطاء SSL، لا User-Agent مزيّف). البانر يُخفى أثناء اللعب (سياسة AdMob).
/// طبقة التوحيد: تُحقن في كل لعبة بعد التحميل دون تعديل ملفاتها.
/// محافِظة عمداً: لا تخفي التمرير ولا تغيّر حجم أي عنصر حتى لا تكسر لعبة.
const String _kWrapperJs = r"""
(function () {
  try {
    if (window.__khayalWrapped) return;
    window.__khayalWrapped = true;
    // منع تكبير الصفحة باللمس (إن لم تكن اللعبة تحدد viewport بنفسها نضيف واحداً)
    var m = document.querySelector('meta[name=viewport]');
    if (!m) {
      m = document.createElement('meta');
      m.name = 'viewport';
      (document.head || document.documentElement).appendChild(m);
      m.content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
    } else if (!/user-scalable/.test(m.content)) {
      m.content += ', maximum-scale=1, user-scalable=no';
    }
    // إزالة وميض اللمس وتحديد النص وقائمة الضغط المطوّل
    var st = document.createElement('style');
    st.textContent = '*{-webkit-tap-highlight-color:transparent;-webkit-touch-callout:none;}' +
      'html,body{-webkit-user-select:none;user-select:none;overscroll-behavior:none;background:#000;}' +
      'input,textarea{-webkit-user-select:text;user-select:text;}';
    (document.head || document.documentElement).appendChild(st);
    document.addEventListener('contextmenu', function (e) { e.preventDefault(); }, true);
    // منع فتح نوافذ/تبويبات جديدة
    window.open = function () { return null; };
    document.addEventListener('click', function (e) {
      var a = e.target && e.target.closest ? e.target.closest('a[target]') : null;
      if (a && a.target && a.target !== '_self') a.target = '_self';
    }, true);

    // مراقبة التحميل الكبير بعد فتح اللعبة (XHR دائماً، وfetch للملفات الكبيرة المعروف حجمها).
    // لا قناة JavaScript: التطبيق يسأل عن الحالة دورياً عبر window.__khayalNet().
    var st = { pending: 0, loaded: 0, total: 0 };
    var xs = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function () {
      var x = this, lastL = 0, lastT = 0, done = false;
      st.pending++;
      x.addEventListener('progress', function (e) {
        if (e.lengthComputable) {
          st.loaded += e.loaded - lastL; lastL = e.loaded;
          if (e.total !== lastT) { st.total += e.total - lastT; lastT = e.total; }
        }
      });
      x.addEventListener('loadend', function () {
        if (!done) { done = true; st.pending = Math.max(0, st.pending - 1); }
      });
      return xs.apply(this, arguments);
    };
    var of = window.fetch;
    if (of) {
      window.fetch = function () {
        st.pending++;
        var p = of.apply(this, arguments), fin = false;
        var end = function () { if (!fin) { fin = true; st.pending = Math.max(0, st.pending - 1); } };
        p.then(function (r) {
          try {
            var len = parseInt(r.headers.get('content-length') || '0', 10);
            if (r.body && len > 1048576 && len < 31457280) {
              st.total += len;
              var rd = r.clone().body.getReader();
              var pump = function () {
                return rd.read().then(function (c) {
                  if (c.done) { end(); return; }
                  st.loaded += c.value.length; return pump();
                });
              };
              pump().catch(end);
              return;
            }
          } catch (e) {}
          end();
        }, end);
        return p;
      };
    }
    window.__khayalNet = function () {
      var o = { pending: st.pending, loaded: st.loaded, total: st.total };
      if (st.pending === 0) { st.loaded = 0; st.total = 0; }
      return JSON.stringify(o);
    };
  } catch (e) {}
})();
""";

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final Map<String, dynamic> _game = AppState.currentGame;
  WebViewController? _controller;
  String _url = '';
  String _host = '';
  String? _status;
  bool _loading = true;
  String _orientation = 'portrait';
  double _progress = 0; // تقدم التحميل الأول (0..1)
  double? _netValue; // تقدم تحميل ما بعد الفتح (null = غير معروف)
  bool _netBusy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    AdsManager.instance.hideBanner(); // لا إعلان فوق مساحة اللعب
    final why = GameLibrary.validate(_game);
    if (_game.isEmpty || why.isNotEmpty) {
      _status = 'تعذّر تشغيل هذه اللعبة.${why.isEmpty ? '' : '\n($why)'}';
      _loading = false;
      return;
    }
    _orientation = ((_game['details_scene'] as Map)['orientation'] ?? 'portrait').toString();
    _applyOrientation();
    _url = ((_game['details_scene'] as Map)['play_url'] ?? '').toString().trim();
    AppState.currentGameUrl = _url;
    final uri = Uri.tryParse(_url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      _status = 'رابط غير آمن';
      _loading = false;
      return;
    }
    _host = uri.host;

    WebViewController? c0;
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // الألعاب تحتاج JS؛ لا يوجد أي JavaScriptChannel
      ..setBackgroundColor(AppColors.gameBg)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          final u = Uri.tryParse(req.url);
          if (u == null) return NavigationDecision.prevent;
          if (!req.isMainFrame) return NavigationDecision.navigate;
          // https فقط وداخل نفس الموقع
          if (u.scheme == 'https' && u.host == _host) return NavigationDecision.navigate;
          return NavigationDecision.prevent;
        },
        onProgress: (p) {
          // لا نعيد بناء الشاشة عند كل نسبة مئوية (يثقل الأجهزة المتوسطة): كل 3% كفاية
          final v = p / 100.0;
          if (mounted && (p >= 100 || (v - _progress).abs() >= 0.03)) setState(() => _progress = v);
        },
        onPageStarted: (_) {
          if (mounted) setState(() {
            _loading = true;
            _progress = 0;
          });
        },
        onPageFinished: (_) {
          c0?.runJavaScript(_kWrapperJs);
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) {
            if (mounted) {
              setState(() {
                _loading = false;
                _status = 'تعذّر تحميل اللعبة.\nتحقق من اتصالك ثم اضغط ⟳';
              });
            }
          }
        },
      ));
    c0 = c;
    _controller = c;
    c.loadRequest(Uri.parse(_url));
    _schedulePoll();
  }

  /// استطلاع حالة التحميل بعد فتح اللعبة: بسرعة (0.7ث) فقط أثناء وجود تحميل جارٍ،
  /// وبوتيرة هادئة (2ث) في اللعب العادي كي لا نستهلك المعالج أثناء اللعب.
  void _schedulePoll() {
    _poll?.cancel();
    _poll = Timer(Duration(milliseconds: _netBusy ? 700 : 2000), () async {
      await _pollNet();
      if (mounted && _controller != null) _schedulePoll();
    });
  }

  Future<void> _pollNet() async {
    final c = _controller;
    if (c == null || _loading || _status != null || !mounted) return;
    try {
      final r = await c.runJavaScriptReturningResult('window.__khayalNet ? window.__khayalNet() : ""');
      var t = r.toString();
      if (t.startsWith('"')) t = jsonDecode(t) as String;
      if (t.isEmpty) return;
      final m = jsonDecode(t) as Map;
      final pending = (m['pending'] as num?)?.toInt() ?? 0;
      final loaded = (m['loaded'] as num?)?.toDouble() ?? 0;
      final total = (m['total'] as num?)?.toDouble() ?? 0;
      final busy = pending > 0;
      final v = (busy && total > 0) ? (loaded / total).clamp(0.0, 1.0).toDouble() : null;
      if (busy != _netBusy || v != _netValue) {
        if (mounted) setState(() {
          _netBusy = busy;
          _netValue = v;
        });
      }
    } catch (_) {}
  }

  void _applyOrientation() {
    switch (_orientation) {
      case 'landscape':
        SystemChrome.setPreferredOrientations(
            [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
        break;
      case 'both':
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
        break;
      default:
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    // التطبيق كله عمودي: نعيد القفل عند الخروج من اللعبة
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _reload() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      _status = null;
      _loading = true;
    });
    c.loadRequest(Uri.parse(_url));
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.of(context).size.shortestSide / 1080; // وحدة التصميم (تصغر الأشرطة في الوضع الأفقي)
    final title = ((_game['main_scene'] is Map ? _game['main_scene']['title_ar'] : '') ?? '').toString();

    return Scaffold(
      backgroundColor: AppColors.gameBg,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 150 * s,
              child: Row(
                children: [
                  _barBtn('→', s, () => Navigator.of(context).maybePop()),
                  SizedBox(width: 20 * s),
                  Expanded(
                    child: Center(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 52 * s, color: Colors.white)),
                    ),
                  ),
                  SizedBox(width: 20 * s),
                  if (_controller != null) _barBtn('⟳', s, _reload) else SizedBox(width: 150 * s),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  if (_controller != null) Positioned.fill(child: WebViewWidget(controller: _controller!)),
                  if (_loading && _status == null)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          NetLoader(width: 220 * s, height: 220 * s, loading: true),
                          SizedBox(height: 40 * s),
                          SizedBox(
                            width: 700 * s,
                            child: _bar(s, _progress, 24 * s),
                          ),
                          SizedBox(height: 16 * s),
                          Text('جارٍ تحميل اللعبة ${(_progress * 100).round()}%',
                              style: TextStyle(fontSize: 38 * s, color: Colors.white70, decoration: TextDecoration.none)),
                        ],
                      ),
                    ),
                  // تحميل كبير بعد فتح اللعبة: شريط رفيع أعلى الشاشة
                  if (!_loading && _status == null && _netBusy)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: Colors.black.withOpacity(0.55),
                        padding: EdgeInsets.fromLTRB(24 * s, 10 * s, 24 * s, 10 * s),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _bar(s, _netValue, 12 * s),
                            SizedBox(height: 6 * s),
                            Text(
                                _netValue == null
                                    ? 'جارٍ تحميل موارد اللعبة...'
                                    : 'جارٍ تحميل موارد اللعبة ${(_netValue! * 100).round()}%',
                                style: TextStyle(fontSize: 30 * s, color: Colors.white70, decoration: TextDecoration.none)),
                          ],
                        ),
                      ),
                    ),
                  if (_status != null)
                    Center(
                      child: Padding(
                        padding: EdgeInsets.all(40 * s),
                        child: Text(_status!,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 44 * s, color: Colors.white, height: 1.4)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(double s, double? value, double height) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation(AppColors.popupBorder),
          ),
        ),
      );

  Widget _barBtn(String t, double s, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 150 * s,
          child: Center(child: Text(t, style: TextStyle(fontSize: 56 * s, color: Colors.white))),
        ),
      );
}
