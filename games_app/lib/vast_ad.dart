import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'config.dart';
import 'nav.dart';

/// إعلان فيديو VAST مباشر (HilltopAds) قبل بدء اللعبة — غير محفَّز، بلا نقاط ولا مكافأة.
/// يعرض صفحة صغيرة فيها مشغّل Google IMA HTML5 داخل WebView تقرأ رابط VAST من [Config.vastTagUrl].
/// القاعدة الذهبية: لا يعلق اللاعب أبداً؛ أي فشل أو تأخر ⇒ تبدأ اللعبة فوراً.
class VastAd {
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _showing = false;

  /// يعرض الإعلان إن مضى الفاصل ثم ينفّذ [proceed] مرة واحدة دائماً.
  static void showThen(VoidCallback proceed) {
    final gap = DateTime.now().difference(_last).inSeconds;
    if (!Config.interstitialOnEnter || _showing || gap < Config.interstitialMinGapSeconds) {
      proceed();
      return;
    }
    _showing = true;
    _last = DateTime.now();
    var done = false;
    void finish() {
      if (done) return;
      done = true;
      _showing = false;
      proceed();
    }

    try {
      Nav.push<void>(const _VastPage()).whenComplete(finish);
    } catch (e) {
      debugPrint('[VAST] $e');
      finish();
    }
  }
}

class _VastPage extends StatefulWidget {
  const _VastPage();
  @override
  State<_VastPage> createState() => _VastPageState();
}

class _VastPageState extends State<_VastPage> {
  late final WebViewController _c;
  Timer? _startTimeout;
  Timer? _hardCap;
  Timer? _closeTimer;
  bool _closed = false;
  bool _started = false;
  bool _canClose = false;
  bool _pageLoaded = false;

  String get _html => '''
<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#c{position:absolute;left:0;top:0;right:0;bottom:0}#v{width:100%;height:100%}</style>
<script src="https://imasdk.googleapis.com/js/sdkloader/ima3.js"></script></head>
<body><div id="c"><video id="v" playsinline></video></div>
<script>
function post(m){try{Ad.postMessage(m)}catch(e){}}
window.onload=function(){
  if(!window.google||!google.ima){post('error');return;}
  var v=document.getElementById('v'),c=document.getElementById('c');
  var dc=new google.ima.AdDisplayContainer(c,v);dc.initialize();
  var loader=new google.ima.AdsLoader(dc);
  loader.addEventListener(google.ima.AdsManagerLoadedEvent.Type.ADS_MANAGER_LOADED,function(e){
    var m=e.getAdsManager(v);
    m.addEventListener(google.ima.AdErrorEvent.Type.AD_ERROR,function(){post('error')});
    m.addEventListener(google.ima.AdEvent.Type.STARTED,function(){post('started')});
    m.addEventListener(google.ima.AdEvent.Type.ALL_ADS_COMPLETED,function(){post('done')});
    m.addEventListener(google.ima.AdEvent.Type.SKIPPED,function(){post('done')});
    m.addEventListener(google.ima.AdEvent.Type.USER_CLOSE,function(){post('done')});
    try{m.init(window.innerWidth,window.innerHeight,google.ima.ViewMode.NORMAL);m.start();}catch(x){post('error')}
  },false);
  loader.addEventListener(google.ima.AdErrorEvent.Type.AD_ERROR,function(){post('error')},false);
  var r=new google.ima.AdsRequest();
  r.adTagUrl='${Config.vastTagUrl}';
  r.linearAdSlotWidth=window.innerWidth;r.linearAdSlotHeight=window.innerHeight;
  loader.requestAds(r);
};
</script></body></html>''';

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('Ad', onMessageReceived: (m) => _onMsg(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _pageLoaded = true,
        // بعد التحميل الأول لا نترك الصفحة تنتقل (نقر الإعلان) كي لا تتعطل الشاشة
        onNavigationRequest: (r) => (_pageLoaded && r.isMainFrame) ? NavigationDecision.prevent : NavigationDecision.navigate,
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? false) _close();
        },
      ));
    try {
      // لتشغيل الفيديو تلقائياً (خاصية خاصة بنسخة أندرويد من المنصة)
      (_c.platform as dynamic).setMediaPlaybackRequiresUserGesture(false);
    } catch (e) {
      debugPrint('[VAST] autoplay: $e');
    }
    // baseUrl: نطاق الموقع المسجّل في HilltopAds
    _c.loadHtmlString(_html, baseUrl: Config.vastPageOrigin);
    _startTimeout = Timer(Duration(seconds: Config.vastStartTimeoutSeconds), () {
      if (!_started) _close();
    });
  }

  void _onMsg(String m) {
    if (m == 'started') {
      _started = true;
      _startTimeout?.cancel();
      _hardCap = Timer(Duration(seconds: Config.vastMaxSeconds), _close);
      _closeTimer = Timer(const Duration(seconds: 12), () {
        if (mounted) setState(() => _canClose = true);
      });
    } else if (m == 'done' || m == 'error') {
      _close();
    }
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _startTimeout?.cancel();
    _hardCap?.cancel();
    _closeTimer?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _closed = true;
    _startTimeout?.cancel();
    _hardCap?.cancel();
    _closeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // لا رجوع أثناء الإعلان؛ المهلات تضمن عدم التعليق
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(children: [
            Positioned.fill(child: WebViewWidget(controller: _c)),
            if (_canClose)
              Positioned(
                top: 6,
                right: 6,
                child: IconButton(
                  onPressed: _close,
                  icon: const Icon(Icons.close, color: Colors.white70, size: 30),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
