import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/ads_manager.dart';
import '../core/app_state.dart';
import '../core/colors.dart';
import '../core/game_library.dart';
import '../widgets/net_loader.dart';

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
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
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
    final credit = _game.isEmpty ? '' : GameLibrary.creditLine(_game);

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
                    Center(child: NetLoader(width: 220 * s, height: 220 * s, loading: true)),
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
            SizedBox(
              height: 90 * s,
              child: Center(
                child: Text(credit,
                    style: TextStyle(fontSize: 34 * s, color: Colors.white.withOpacity(0.6))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barBtn(String t, double s, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 150 * s,
          child: Center(child: Text(t, style: TextStyle(fontSize: 56 * s, color: Colors.white))),
        ),
      );
}
