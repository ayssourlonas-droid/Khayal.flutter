import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'alert_popup.dart';
import 'app_state.dart';
import 'colors.dart';
import 'design.dart';
import 'divided_images.dart';
import 'rating_bar.dart';
import 'ui_image.dart';

/// أجزاء شاشة التفاصيل التي لا تعتمد على حالتها: صفوف التقييم، صفحات الكاروسيل
/// (المعرض/الوصف/الطاقم) والمشاركة والإبلاغ. استُخرجت من details_screen.dart كما هي.

const _reportReasons = [
  'اللعبة لا تفتح',
  'شاشة سوداء أو فارغة',
  'تعليق أو بطء شديد',
  'اللمس أو الأزرار لا تعمل',
  'محتوى غير مناسب',
  'مخالفة حقوق / رخصة',
  'مشكلة أخرى',
];

Future<void> shareAppLink(BuildContext context) async {
  if (AppState.appPageUrl.isEmpty) {
    await showAlertPopup(context,
        title: 'غير متاح حالياً',
        message: 'رابط مشاركة التطبيق غير متوفر حالياً، حاول لاحقاً.',
        buttons: const [PopupBtn(' حسناً ', 1)]);
    return;
  }
  await Clipboard.setData(ClipboardData(text: AppState.appPageUrl));
  if (!context.mounted) return;
  await showAlertPopup(context,
      title: 'تم النسخ ✅',
      message: 'تم نسخ رابط التطبيق. شاركه مع أصدقائك!',
      buttons: const [PopupBtn(' موافق ', 2)]);
}

/// إبلاغ عن مشكلة في اللعبة: يختار اللاعب السبب فيُجهَّز نص البلاغ ويُفتح بريد/واتساب الدعم.
/// (لا خادم لدينا: النص يُنسخ أيضاً إلى الحافظة.)
Future<void> reportGame(BuildContext context, Map<String, dynamic> game,
    Map<String, dynamic> main, Map<String, dynamic> details) async {
  final reason = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF14091F),
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('ما المشكلة في هذه اللعبة؟',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            for (final r in _reportReasons)
              ListTile(title: Text(r, style: const TextStyle(color: Colors.white)), onTap: () => Navigator.pop(c, r)),
            ListTile(
                title: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
                onTap: () => Navigator.pop(c)),
          ],
        ),
      ),
    ),
  );
  if (reason == null || !context.mounted) return;

  String version = '';
  try {
    version = (await PackageInfo.fromPlatform()).version;
  } catch (_) {}
  final title = (main['title_ar'] ?? '').toString();
  final subject = 'بلاغ عن لعبة: $title';
  final body = 'اللعبة: $title (#${game['id'] ?? ''})\n'
      'المشكلة: $reason\n'
      'الرابط: ${details['play_url'] ?? ''}\n'
      'إصدار التطبيق: $version';
  await Clipboard.setData(ClipboardData(text: '$subject\n$body'));

  String? target;
  if (AppState.supportEmail.isNotEmpty) {
    target = 'mailto:${AppState.supportEmail}?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';
  } else if (AppState.supportWhatsappUrl.isNotEmpty) {
    target = AppState.supportWhatsappUrl;
  }
  if (target != null) {
    try {
      await launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
  if (!context.mounted) return;
  await showAlertPopup(context,
      title: 'شكراً لك ✅',
      message: target == null
          ? 'وسيلة التواصل غير متوفرة الآن، لكن نُسخ نص البلاغ؛ أرسله لنا لاحقاً.'
          : 'جُهّز البلاغ وفُتح تطبيق الإرسال. إن لم يظهر فقد نُسخ النص إلى الحافظة.',
      buttons: const [PopupBtn(' موافق ', 2)]);
}

Widget ratingRow(double value, String tape, Color tint, String caption) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    textDirection: TextDirection.ltr,
    children: [
      Container(
        width: 300,
        height: 45,
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(4)),
        child: RatingBar(
          value: value,
          max: 100,
          width: 300,
          height: 45,
          tapeAsset: tape,
          maskAsset: 'assets/images/a1k.webp',
        ),
      ),
      const SizedBox(width: 6),
      Container(
        width: 100,
        height: 45,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color.fromRGBO(0, 0, 0, 0.49), Color.fromRGBO(184, 121, 189, 0.49)]),
        ),
        child: Text(caption, style: const TextStyle(fontSize: 28, color: Colors.white, decoration: TextDecoration.none)),
      ),
    ],
  );
}

Widget detailsPage(String title, Widget body) => Column(
      children: [
        SizedBox(
          width: 980,
          height: 70,
          child: Center(
            child: OutlinedText(title,
                size: 45, color: const Color.fromRGBO(255, 59, 59, 1), outlineColor: const Color.fromRGBO(15, 0, 15, 1), outline: 15),
          ),
        ),
        SizedBox(width: 980, height: 480, child: body),
      ],
    );

Widget descriptionBox(String description, String credit) => SingleChildScrollView(
      child: Column(
        children: [
          if (description.isNotEmpty)
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 50, color: Colors.white, height: 1.15, decoration: TextDecoration.none),
            ),
          if (credit.isNotEmpty) ...[
            const SizedBox(height: 36),
            Text(
              credit,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 38, color: Color(0xFFB39DDB), height: 1.2, decoration: TextDecoration.none),
            ),
          ],
        ],
      ),
    );

Widget specialGallery(List<Map<String, dynamic>> special) => ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: special.length,
      separatorBuilder: (_, __) => const SizedBox(width: 20),
      itemBuilder: (_, i) {
        final it = special[i];
        final raw = [it['main_photo_url'], it['sub_photo_url'], it['extra_photo_url']]
            .map((e) => (e ?? '').toString().trim())
            .where((u) => u.isNotEmpty && u != '0' && u.startsWith('http'))
            .toList();
        return SizedBox(
          width: 350,
          height: 500,
          child: Column(
            children: [
              DividedImages(urls: raw, width: 350, height: 400),
              SizedBox(
                height: 100,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: OutlinedText((it['item_name'] ?? 'مجهول').toString(),
                      size: 45, outline: 10, outlineColor: AppColors.purpleOutline),
                ),
              ),
            ],
          ),
        );
      },
    );

Widget castList(List<Map<String, dynamic>> cast) => ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: cast.length,
      separatorBuilder: (_, __) => const SizedBox(width: 20),
      itemBuilder: (_, i) {
        final a = cast[i];
        final url = (a['photo_url'] ?? '').toString().trim();
        return SizedBox(
          width: 150,
          height: 200,
          child: Column(
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: url.startsWith('http') ? NetImage(url: url, width: 150, height: 150) : const SizedBox.shrink(),
              ),
              Expanded(
                child: Text(
                  (a['original_name'] ?? '').toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, color: Colors.white, decoration: TextDecoration.none),
                ),
              ),
            ],
          ),
        );
      },
    );
