import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ads_manager.dart';
import 'app_state.dart';
import 'colors.dart';
import 'player_points.dart';
import 'alert_popup.dart';
import 'design.dart';
import 'glow_button.dart';
import 'sound_fx.dart';

/// يقابل SettingsScreen.gd/.tscn — النقاط، التواصل، المشاركة، الملاحظات، وإعلان المكافأة.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _unavailable(BuildContext c, String msg) =>
      showAlertPopup(c, title: 'غير متاح حالياً', message: msg, buttons: const [PopupBtn(' حسناً ', 1)]);

  Future<void> _contact(BuildContext c) async {
    final buttons = <PopupBtn>[];
    final ids = <String>[];
    if (AppState.supportWhatsappUrl.isNotEmpty) {
      buttons.add(const PopupBtn(' واتساب ', 2));
      ids.add('whatsapp');
    }
    if (AppState.supportEmail.isNotEmpty) {
      buttons.add(const PopupBtn(' البريد ', 3));
      ids.add('email');
    }
    if (buttons.isEmpty) {
      return _unavailable(c, 'وسائل التواصل غير متوفرة حالياً، حاول لاحقاً.');
    }
    final r = await showAlertPopup(c, title: 'تواصل معنا', message: 'اختر وسيلة التواصل المناسبة لك:', buttons: buttons);
    if (ids[r] == 'whatsapp') {
      _open(AppState.supportWhatsappUrl);
    } else {
      _open('mailto:${AppState.supportEmail}');
    }
  }

  Future<void> _share(BuildContext c) async {
    if (AppState.appPageUrl.isEmpty) {
      return _unavailable(c, 'رابط مشاركة التطبيق غير متوفر حالياً، حاول لاحقاً.');
    }
    await Clipboard.setData(ClipboardData(text: AppState.appPageUrl));
    if (!c.mounted) return;
    await showAlertPopup(c,
        title: 'تم النسخ ✅',
        message: 'تم نسخ رابط التطبيق. شاركه مع أصدقائك!',
        buttons: const [PopupBtn(' موافق ', 2)]);
  }

  Future<void> _feedback(BuildContext c) async {
    if (AppState.feedbackUrl.isEmpty) {
      return _unavailable(c, 'صفحة الإبلاغ عن المشاكل غير متوفرة حالياً، حاول لاحقاً.');
    }
    _open(AppState.feedbackUrl);
  }

  Future<void> _legal(BuildContext c) async {
    final items = <String, String>{
      if (AppState.termsUrl.isNotEmpty) 'terms': AppState.termsUrl,
      if (AppState.privacyUrl.isNotEmpty) 'privacy': AppState.privacyUrl,
    };
    if (items.isEmpty) return _unavailable(c, 'صفحة الشروط والخصوصية غير متوفرة حالياً، حاول لاحقاً.');
    if (items.length == 1) return _open(items.values.first);
    final r = await showAlertPopup(c,
        title: 'القانونية',
        message: 'اختر الصفحة التي تريد قراءتها:',
        buttons: const [PopupBtn(' الشروط ', 3), PopupBtn(' الخصوصية ', 5)]);
    _open(r == 0 ? items['terms']! : items['privacy']!);
  }

  Future<void> _credits(BuildContext c) async {
    if (AppState.creditsUrl.isEmpty) {
      return _unavailable(c, 'صفحة حقوق الألعاب غير متوفرة حالياً، حاول لاحقاً.');
    }
    _open(AppState.creditsUrl);
  }

  Future<void> _ad(BuildContext c) async {
    // المكافأة تُضاف داخل AdsManager عند إكمال المشاهدة، والواجهة تتحدث تلقائياً.
    if (!AdsManager.instance.showRewarded()) {
      await showAlertPopup(c,
          title: 'تنبيه',
          message: 'الإعلان غير جاهز الآن، حاول بعد لحظات.',
          buttons: const [PopupBtn(' موافق ', 2)]);
    }
  }

  static const _font = 'Tajawal';
  static const _lav = Color(0xFFE3B8FF); // نص ثانوي بنفسجي فاتح
  static const _card = Color(0xB3100418); // خلفية البطاقات (داكنة شبه شفافة)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: _font, decoration: TextDecoration.none),
        child: Column(
          children: [
            const _BannerStrip(),
            Expanded(
              child: GodotGradientBox(
                homeGradient, // نفس خلفية الصفحة الرئيسية
                child: Design(builder: (ctx, h) => _content(ctx)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext ctx) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 30, 40, 60),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _topBar(ctx),
            const SizedBox(height: 36),
            _adHero(ctx),
            const SizedBox(height: 44),
            _section('الدعم والمشاركة'),
            _group([
              _item(Icons.support_agent, 'تواصل معنا للدعم الفني', () => _contact(ctx)),
              _item(Icons.share, 'شارك التطبيق مع أصدقائك', () => _share(ctx)),
              _item(Icons.bug_report, 'هل واجهت مشكلة؟ رأيك يهمنا', () => _feedback(ctx)),
            ]),
            const SizedBox(height: 40),
            _section('معلومات'),
            _group([
              _item(Icons.gavel, 'الشروط والخصوصية', () => _legal(ctx)),
              _item(Icons.groups, 'حقوق الألعاب والمطورين', () => _credits(ctx)),
            ]),
            const SizedBox(height: 40),
            _section('التطبيق'),
            _group([_soundItem()]),
          ],
        ),
      ),
    );
  }

  // الصف العلوي: رجوع (يمين) — العنوان — النقاط (يسار)
  Widget _topBar(BuildContext ctx) {
    return SizedBox(
      height: 110,
      child: Row(
        children: [
          GlowButton(
            sound: Sfx.back,
            onTap: () => Navigator.of(ctx).maybePop(),
            child: SizedBox(width: 120, height: 70, child: Image.asset('assets/images/a1c.webp', fit: BoxFit.contain)),
          ),
          const Expanded(
            child: Text('الإعدادات',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 64, fontWeight: FontWeight.w800, color: Colors.white, shadows: [
                  Shadow(color: AppColors.cardShadow, blurRadius: 18),
                ])),
          ),
          ListenableBuilder(
            listenable: PlayerPoints.instance,
            builder: (_, __) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: AppColors.yellowLabel, width: 3),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.stars, color: AppColors.yellowLabel, size: 46),
                const SizedBox(width: 10),
                Text('${PlayerPoints.instance.points}',
                    style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w800, color: AppColors.yellowLabel)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // بطاقة الإعلان: الأولى والأكبر والوحيدة بحدّ أصفر لأنها الطريق لكسب نقطة
  Widget _adHero(BuildContext ctx) {
    return GlowButton(
      onTap: () => _ad(ctx),
      child: Container(
        height: 250,
        padding: const EdgeInsets.symmetric(horizontal: 30),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF8A12B0), Color(0xFF3A0852)],
          ),
          borderRadius: BorderRadius.circular(44),
          border: Border.all(color: AppColors.yellowLabel, width: 5),
          boxShadow: [BoxShadow(color: AppColors.yellowLabel.withOpacity(0.30), blurRadius: 34, spreadRadius: 2)],
        ),
        child: Row(
          children: [
            SizedBox(width: 230, height: 170, child: Image.asset('assets/images/a1b.webp', fit: BoxFit.contain)),
            const SizedBox(width: 26),
            Expanded(
              child: ListenableBuilder(
                listenable: AdsManager.instance,
                builder: (_, __) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('شاهد إعلاناً واحصل على نقطة',
                        style: TextStyle(fontSize: 62, height: 1.15, fontWeight: FontWeight.w800, color: AppColors.yellowLabel)),
                    const SizedBox(height: 10),
                    Text(AdsManager.instance.isRewardedReady ? 'نقطة واحدة لكل إعلان تكمل مشاهدته' : 'جارٍ تجهيز الإعلان…',
                        style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w500, color: _lav)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(right: 14, bottom: 14),
        child: Text(t, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w700, color: _lav)),
      );

  Widget _group(List<Widget> rows) {
    final kids = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) kids.add(const Divider(height: 3, thickness: 2, indent: 30, endIndent: 30, color: Color(0x55AD00BA)));
      kids.add(rows[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: AppColors.purpleOutline, width: 3),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(37), child: Column(children: kids)),
    );
  }

  Widget _iconCircle(IconData icon) => Container(
        width: 84,
        height: 84,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [Color(0xFFC21AE0), Color(0xFF6A0DAD)], begin: Alignment.topRight, end: Alignment.bottomLeft),
        ),
        child: Icon(icon, color: Colors.white, size: 46),
      );

  Widget _item(IconData icon, String text, VoidCallback onTap) {
    return GlowButton(
      onTap: onTap,
      child: Container(
        height: 124,
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Row(children: [
          _iconCircle(icon),
          const SizedBox(width: 26),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w700, color: Colors.white))),
          const Icon(Icons.chevron_left, color: _lav, size: 56),
        ]),
      ),
    );
  }

  Widget _soundItem() {
    return ValueListenableBuilder<bool>(
      valueListenable: SoundFx.instance.enabled,
      builder: (_, on, __) => GlowButton(
        onTap: () => SoundFx.instance.setEnabled(!on),
        child: Container(
          height: 124,
          color: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Row(children: [
            _iconCircle(on ? Icons.volume_up : Icons.volume_off),
            const SizedBox(width: 26),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('الأصوات', style: TextStyle(fontSize: 46, fontWeight: FontWeight.w700, color: Colors.white)),
                Text(on ? 'مفعّلة' : 'موقوفة', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w500, color: _lav)),
              ]),
            ),
            // مفتاح تشغيل مرسوم يدوياً
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 116,
              height: 62,
              padding: const EdgeInsets.all(6),
              alignment: on ? Alignment.centerLeft : Alignment.centerRight,
              decoration: BoxDecoration(
                color: on ? AppColors.yellowLabel : const Color(0xFF4A3454),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: on ? Colors.black : Colors.white54, shape: BoxShape.circle),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// شريط البانر في أعلى الشاشة (مثل الرئيسية) ببانر خاص بهذه الشاشة.
class _BannerStrip extends StatefulWidget {
  const _BannerStrip();
  @override
  State<_BannerStrip> createState() => _BannerStripState();
}

class _BannerStripState extends State<_BannerStrip> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = AdsManager.instance.createExtraBanner(onLoaded: () {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;
    final ad = _ad;
    return Container(
      color: Colors.black,
      width: double.infinity,
      padding: EdgeInsets.only(top: topInset),
      alignment: Alignment.center,
      child: (ad == null || !_loaded)
          ? const SizedBox.shrink()
          : SizedBox(width: ad.size.width.toDouble(), height: ad.size.height.toDouble(), child: AdWidget(ad: ad)),
    );
  }
}
