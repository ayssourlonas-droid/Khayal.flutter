import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/ads_manager.dart';
import '../core/app_state.dart';
import '../core/colors.dart';
import '../core/player_points.dart';
import '../widgets/alert_popup.dart';
import '../widgets/design.dart';
import '../widgets/glow_button.dart';

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

  Future<void> _ad(BuildContext c) async {
    // المكافأة تُضاف داخل AdsManager عند إكمال المشاهدة، والواجهة تتحدث تلقائياً.
    if (!AdsManager.instance.showRewarded()) {
      await showAlertPopup(c,
          title: 'تنبيه',
          message: 'الإعلان غير جاهز الآن، حاول بعد لحظات.',
          buttons: const [PopupBtn(' موافق ', 2)]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Design(
        builder: (ctx, h) => Stack(
          children: [
            // الجسم (من y=200)
            Positioned(top: 200, left: 0, right: 0, bottom: 0, child: GodotGradientBox(settingsBodyGradient)),
            // الرأس 200
            Positioned(top: 0, left: 0, right: 0, height: 200, child: GodotGradientBox(settingsTopGradient)),
            // زينة (y=210، ارتفاع 120)
            Positioned(top: 210, left: 0, right: 0, height: 120, child: GodotGradientBox(settingsDecorGradient)),
            // النقاط
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              height: 100,
              child: ListenableBuilder(
                listenable: PlayerPoints.instance,
                builder: (_, __) => Center(
                  child: Text('النقاط: ${PlayerPoints.instance.points}',
                      style: const TextStyle(
                          fontSize: 60, color: AppColors.yellowLabel, decoration: TextDecoration.none)),
                ),
              ),
            ),
            // الصفوف
            Positioned(
              top: 220,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  _row('تواصل معنا للدعم الفني', 'assets/images/m2_a1l.png', () => _contact(ctx)),
                  const SizedBox(height: 20),
                  _row('شارك التطبيق مع أصدقائك', 'assets/images/m2_a1l.png', () => _share(ctx)),
                  const SizedBox(height: 20),
                  _row('هل واجهت مشكلة؟ رأيك يهمنا', 'assets/images/m2_a1l.png', () => _feedback(ctx)),
                  const SizedBox(height: 20),
                  _row('شاهد اعلان للحصول علا نقطة', 'assets/images/a1b.webp', () => _ad(ctx)),
                ],
              ),
            ),
            // زر رجوع (إضافة: الأصل كان يعتمد على زر الرجوع في النظام)
            Positioned(
              right: 25,
              top: 105,
              child: GlowButton(
                onTap: () => Navigator.of(ctx).maybePop(),
                child: SizedBox(width: 120, height: 60, child: Image.asset('assets/images/a1c.webp', fit: BoxFit.contain)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String text, String icon, VoidCallback onTap) {
    return SizedBox(
      height: 100,
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 60, color: AppColors.yellowLabel, decoration: TextDecoration.none)),
          ),
          GlowButton(
            onTap: onTap,
            child: SizedBox(width: 170, height: 100, child: Image.asset(icon, fit: BoxFit.contain)),
          ),
        ],
      ),
    );
  }
}
