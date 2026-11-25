import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as m;
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_tables.dart';

/// لغة واجهة خيال نفسها: تلقائي (لغة الجهاز) | العربية | English.
/// المصدر عربي. الترجمة بمطابقة نص الواجهة (مطبَّعاً: مسافات مطوية وأرقام ← {#}) على [_en]؛ ما لا ترجمة له يبقى عربياً.
/// تصميم الواجهة بمقاسات من اليمين لليسار فلا نقلب الاتجاه العام: النص الإنجليزي وحده يُعرض LTR داخل مكانه.
class L10n {
  L10n._();
  static const auto = 'auto';
  static const _prefKey = 'ui_lang';
  static const Map<String, String> options = {
    'ar': 'العربية', 'en': 'English', 'fr': 'Français', 'es': 'Español', 'pt': 'Português', 'de': 'Deutsch',
    'ru': 'Русский', 'tr': 'Türkçe', 'zh-CN': '中文', 'hi': 'हिन्दी',
  };

  static final ValueNotifier<String> lang = ValueNotifier<String>(auto);

  static Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(_prefKey) ?? auto;
      lang.value = (v == auto || options.containsKey(v)) ? v : auto;
    } catch (_) {}
  }

  static Future<void> set(String v) async {
    lang.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefKey, v);
    } catch (_) {}
  }

  /// اللغة الفعلية: المختارة، أو لغة الجهاز إن كانت مدعومة، وإلا الإنجليزية.
  static String get resolved {
    final v = lang.value;
    if (v != auto) return v;
    final c = ui.PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    if (c == 'zh') return 'zh-CN';
    return options.containsKey(c) ? c : 'en';
  }

  static bool get isAr => resolved == 'ar';

  static final RegExp _num = RegExp(r'[0-9]+(?:[.,][0-9]+)*');
  static final RegExp _ws = RegExp(r'\s+');

  /// يترجم نص واجهة عربياً إلى لغة الواجهة الحالية؛ يرجع الأصل إن لم توجد ترجمة.
  static String tr(String s) {
    if (isAr) return s;
    final mt = RegExp(r'^(\s*)([\s\S]*?)(\s*)$').firstMatch(s);
    if (mt == null) return s;
    final core = mt.group(2)!.replaceAll(_ws, ' ');
    if (core.isEmpty) return s;
    final nums = <String>[];
    final key = core.replaceAllMapped(_num, (x) {
      nums.add(x[0]!);
      return '{#}';
    });
    final v = (kUiTables[resolved] ?? const <String, String>{})[key] ?? _en[key];
    if (v == null) return s;
    final out = v.replaceAllMapped(RegExp(r'\{(\d+)\}'), (x) {
      final i = int.parse(x[1]!) - 1;
      return i < nums.length ? nums[i] : '';
    });
    return '${mt.group(1)}$out${mt.group(3)}';
  }

  static const Map<String, String> _en = {
    'حسناً': 'OK',
    'موافق': 'OK',
    'إلغاء': 'Cancel',
    'تجاوز': 'Skip',
    'تحديث ⬆️': 'Update ⬆️',
    'القائمة فارغة - أضف ملفات صوتية': 'The list is empty - add audio files',
    '⚠️ تعذر تحميل الملف': '⚠️ Could not load the file',
    '🎵 مشغل الصوت': '🎵 Audio player',
    'لا يوجد ملف صوتي محدد': 'No audio file selected',
    '📋 القائمة': '📋 Playlist',
    'اللعبة لا تفتح': "The game won't open",
    'شاشة سوداء أو فارغة': 'Black or blank screen',
    'تعليق أو بطء شديد': 'Freezing or severe lag',
    'اللمس أو الأزرار لا تعمل': "Touch or buttons don't work",
    'محتوى غير مناسب': 'Inappropriate content',
    'مخالفة حقوق / رخصة': 'Copyright / license violation',
    'مشكلة أخرى': 'Other problem',
    'غير متاح حالياً': 'Not available right now',
    'رابط مشاركة التطبيق غير متوفر حالياً، حاول لاحقاً.': 'The app share link is not available right now. Try again later.',
    'تم النسخ ✅': 'Copied ✅',
    'تم نسخ رابط التطبيق. شاركه مع أصدقائك!': 'App link copied. Share it with your friends!',
    'ما المشكلة في هذه اللعبة؟': "What's wrong with this game?",
    'شكراً لك ✅': 'Thank you ✅',
    'وسيلة التواصل غير متوفرة الآن، لكن نُسخ نص البلاغ؛ أرسله لنا لاحقاً.': 'Contact method is unavailable right now, but the report text was copied; send it to us later.',
    'جُهّز البلاغ وفُتح تطبيق الإرسال. إن لم يظهر فقد نُسخ النص إلى الحافظة.': 'The report is ready and the sending app was opened. If it did not appear, the text was copied to the clipboard.',
    'مجهول': 'Unknown',
    'قيّم هذه اللعبة': 'Rate this game',
    'إزالة تقييمي': 'Remove my rating',
    'سنة الصدور :': 'Release year:',
    'خيال': 'Khayal',
    'الجمهور': 'Audience',
    'إعجاب': 'Like',
    'تقييمي {#}': 'My rating {1}',
    'تقييم': 'Rating',
    'مفضلة': 'Favorite',
    'معرض': 'Gallery',
    'وصف': 'About',
    'طاقم': 'Credits',
    'إبلاغ': 'Report',
    'مشاركة': 'Share',
    'معرض الصور': 'Gallery',
    'الوصف': 'Description',
    'الطاقم': 'Credits',
    'تابع اللعب': 'Continue playing',
    'تابع ▶': 'Continue ▶',
    'المفضلة': 'Favorites',
    'اضغط ⭐ على أي لعبة لتظهر هنا وتصل إليها بسرعة.': 'Tap ⭐ on any game to see it here and reach it quickly.',
    'لعبة اليوم': 'Game of the day',
    'جرّبها': 'Try it',
    'اقتراحات اليوم لك': "Today's picks for you",
    'الترتيب': 'Sort',
    'الافتراضي': 'Default',
    'الأعلى تقييماً': 'Top rated',
    'الأحدث': 'Newest',
    'التصنيف': 'Category',
    'الكل': 'All',
    'ابحث عن لعبة...': 'Search for a game...',
    'لا توجد نتائج مطابقة': 'No matching results',
    'لغة نصوص الألعاب': 'Game text language',
    'لغة التطبيق': 'App language',
    'تلقائي (لغة الجهاز)': 'Automatic (device language)',
    'الأصلية بلا ترجمة': 'Original, no translation',
    'رابط غير آمن': 'Unsafe link',
    'تعذّر تحميل اللعبة.\nتحقق من اتصالك ثم اضغط ⟳': 'Could not load the game.\nCheck your connection, then tap ⟳',
    'تعذّر تحميل اللعبة. تحقق من اتصالك ثم اضغط ⟳': 'Could not load the game. Check your connection, then tap ⟳',
    'جارٍ تحميل اللعبة {#}%': 'Loading game {1}%',
    'جارٍ تحميل موارد اللعبة...': 'Loading game resources...',
    'جارٍ تحميل موارد اللعبة {#}%': 'Loading game resources {1}%',
    'العب الآن.. ألعاب ممتعة في جيبك.': 'Play now.. fun games in your pocket.',
    'جاري تجهيز مكتبة الألعاب...': 'Getting the games library ready...',
    'تحدَّ نفسك، وحطّم رقمك القياسي!': 'Challenge yourself and break your record!',
    'ألعاب خفيفة تعمل مباشرة بلا تحميل.': 'Light games that run instantly, no download.',
    'ابحث عن لعبتك المفضلة وابدأ اللعب.': 'Find your favorite game and start playing.',
    'هل جربت لعبة جديدة اليوم؟': 'Have you tried a new game today?',
    'مجموعة ألعاب تتجدد باستمرار.': 'A collection of games that keeps growing.',
    'شاهد إعلاناً قصيراً لتحصل على نقطة لعب.': 'Watch a short ad to earn a play point.',
    'نحترم حقوق المطورين.. كل لعبة مذكور مطوّرها ورخصتها.': "We respect developers' rights.. every game lists its developer and license.",
    'جاري جلب آخر الألعاب المضافة...': 'Fetching the latest added games...',
    'استرخِ.. نحن نجهّز لك المتعة.': 'Relax.. we are getting the fun ready.',
    'هل واجهت مشكلة؟ تواصل معنا من الإعدادات.': 'Having a problem? Contact us from Settings.',
    'رأيك يهمنا.. ساعدنا في تحسين التطبيق.': 'Your opinion matters.. help us improve the app.',
    'هل تعلم؟ يمكنك تغيير الثيم من الإعدادات.': 'Did you know? You can change the theme in Settings.',
    'المتعة تبدأ الآن.. شكراً لانتظارك.': 'The fun starts now.. thanks for waiting.',
    'واتساب': 'WhatsApp',
    'البريد': 'Email',
    'وسائل التواصل غير متوفرة حالياً، حاول لاحقاً.': 'Contact methods are not available right now. Try again later.',
    'تواصل معنا': 'Contact us',
    'اختر وسيلة التواصل المناسبة لك:': 'Choose the contact method that suits you:',
    'صفحة الإبلاغ عن المشاكل غير متوفرة حالياً، حاول لاحقاً.': 'The problem-report page is not available right now. Try again later.',
    'صفحة الشروط والخصوصية غير متوفرة حالياً، حاول لاحقاً.': 'The terms and privacy page is not available right now. Try again later.',
    'القانونية': 'Legal',
    'اختر الصفحة التي تريد قراءتها:': 'Choose the page you want to read:',
    'الشروط': 'Terms',
    'الخصوصية': 'Privacy',
    'صفحة حقوق الألعاب غير متوفرة حالياً، حاول لاحقاً.': 'The game credits page is not available right now. Try again later.',
    'تنبيه': 'Notice',
    'الإعلان غير جاهز الآن، حاول بعد لحظات.': 'The ad is not ready yet. Try again in a moment.',
    'الدعم والمشاركة': 'Support & sharing',
    'تواصل معنا للدعم الفني': 'Contact us for support',
    'شارك التطبيق مع أصدقائك': 'Share the app with your friends',
    'هل واجهت مشكلة؟ رأيك يهمنا': 'Had a problem? We value your feedback',
    'معلومات': 'About',
    'الشروط والخصوصية': 'Terms & privacy',
    'حقوق الألعاب والمطورين': 'Game & developer credits',
    'التطبيق': 'App',
    'الإعدادات': 'Settings',
    'شاهد إعلاناً واحصل على نقطة': 'Watch an ad and earn a point',
    'نقطة واحدة لكل إعلان تكمل مشاهدته': 'One point for every ad you finish watching',
    'جارٍ تجهيز الإعلان…': 'Preparing the ad…',
    'الأصوات': 'Sounds',
    'مفعّلة': 'On',
    'موقوفة': 'Off',
    'تنبيه !': 'Notice!',
    'يرجى العلم أن التطبيق ما زال قيد التطوير، وقد تواجهكم بعض المشكلات. نرجو منكم التفهم.❤️': 'Please note the app is still under development and you may run into some issues. Thank you for your understanding.❤️',
    '⚠️ تعثّر فحص الإصدار': '⚠️ Version check failed',
    'تعثّر فحص إصدار التطبيق. يرجى ترقية التطبيق إلى آخر إصدار.': 'The app version check failed. Please update the app to the latest version.',
    'يوجد إصدار جديد إلزامي من التطبيق. يجب التحديث للمتابعة.': 'A new mandatory version is available. You must update to continue.',
    'يتوفر إصدار جديد من التطبيق. يُنصح بالتحديث للحصول على أحدث الميزات والإصلاحات.': 'A new version is available. Updating is recommended to get the latest features and fixes.',
    '🔄 يتوفر تحديث': '🔄 Update available',
  };
}

/// بديل لـ Text من material: يترجم نص الواجهة العربي تلقائياً ويعيد البناء عند تغيّر اللغة.
/// يستعمل في الملفات بـ: import 'package:flutter/material.dart' hide Text; import 'l10n.dart';
class Text extends m.StatelessWidget {
  final String data;
  final m.TextStyle? style;
  final m.StrutStyle? strutStyle;
  final m.TextAlign? textAlign;
  final m.TextDirection? textDirection;
  final ui.Locale? locale;
  final bool? softWrap;
  final m.TextOverflow? overflow;
  final m.TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final m.TextWidthBasis? textWidthBasis;
  final ui.TextHeightBehavior? textHeightBehavior;
  final m.Color? selectionColor;

  const Text(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  @override
  m.Widget build(m.BuildContext context) {
    return m.ValueListenableBuilder<String>(
      valueListenable: L10n.lang,
      builder: (_, __, ___) {
        final out = L10n.tr(data);
        final translated = !identical(out, data) && out != data;
        return m.Text(
          out,
          style: style,
          strutStyle: strutStyle,
          // نص مترجم لغير العربية يُعرض LTR داخل موضعه (التصميم نفسه يبقى من اليمين)
          textAlign: translated && (textAlign == null || textAlign == m.TextAlign.start) ? m.TextAlign.left : textAlign,
          textDirection: translated ? ui.TextDirection.ltr : textDirection,
          locale: locale,
          softWrap: softWrap,
          overflow: overflow,
          textScaler: textScaler,
          maxLines: maxLines,
          semanticsLabel: semanticsLabel,
          textWidthBasis: textWidthBasis,
          textHeightBehavior: textHeightBehavior,
          selectionColor: selectionColor,
        );
      },
    );
  }
}
