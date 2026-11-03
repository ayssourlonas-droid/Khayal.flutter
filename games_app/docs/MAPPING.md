# جدول التحويل: Godot ← Flutter

| Godot (الأصل) | Flutter (الجديد) | ملاحظات |
|---|---|---|
| `Config.gd` | `lib/config.dart` | نفس الروابط والتراخيص + معرّفات AdMob |
| `GameLibrary.gd` | `lib/game_library.dart` | نفس شروط التحقق الخمسة |
| `GlobalState.gd` | `lib/app_state.dart` | الحالة المشتركة |
| `PlayerPoints.gd` | `lib/player_points.dart` | `shared_preferences` بدل `user://player_points.save` |
| `AdsManager.gd` | `lib/ads_manager.dart` | `google_mobile_ads`: موافقة UMP ← تهيئة ← بانر + مكافأة (نقطة/إعلان) |
| `MovieLoader.gd` (بيانات) | `lib/data_repository.dart` | ذاكرة ← قرص ← شبكة + تحديث صامت، `?v=`، مهلة 15 ث، يجب أن يكون JSON مصفوفة |
| `MovieLoader.gd` (صور) | `ImageStore` | حد أقصى تنزيلين متوازيين + كاش |
| `SceneTransition.gd` | `lib/nav.dart` | تلاشٍ 0.3 ث + قفل الانتقال، نفس لون التلاشي |
| `AlertPopup.gd` | `lib/alert_popup.dart` | 800×500، 1–3 أزرار 220×100، نفس لوحة الألوان والحركة 0.25/0.2 ث |
| `ButtonGlow.gd` + `the_buttons_glow.gdshader` | `lib/glow_button.dart` + `lib/button_glow.frag` | شيدر حقيقي، دمج إضافي، 0.5 ث، تقدّم 0→1.4 |
| `NetLoader.gd` + `net_loader.gdshader` | `lib/net_loader.dart` + `lib/net_loader.frag` | شيدر حقيقي؛ كشف wlan/بيانات كل ثانية؛ تلاشٍ 0.5 ث |
| `tape_movement.gdshader` | `lib/rating_bar.dart` | CustomPainter: شريط متحرك (0.2/ث) مقنّع بالنجوم |
| `top_page_movement.gdshader` | حركة `Transform` في `details_screen`/`audio_player_screen` | إزاحة دائرية 1% بسرعة 0.5 — مطابقة رياضياً (الإزاحة في UV = إزاحة الصورة) |
| `divided_into_3_images.gdshader` | `lib/divided_images.dart` | CustomPainter. **تنبيه:** الشيدر الأصلي لا يقصّ الصور بمناطقها فتغطي الأولى الباقي؛ النسخة الجديدة تقصّها حسب التصميم المقصود (انظر التعليق بأعلى الملف) |
| `TitleMarquee.gd` | `lib/title_marquee.dart` | الأصل كان يحمّل شيدراً غير موجود بالمشروع (معطّل)؛ النسخة الجديدة تعمل فعلاً |
| `PageScroll.gd` | `lib/pull_refresh.dart` | عتبة 80، أقصى 130، أقصى ارتداد سفلي 60، هالة بيضاء 300×120، مهلة 20 ث، حجب نقرات 400 ms |
| `MovieTemplate.tscn` | `lib/game_card.dart` | 317×520، بوستر 300×400، شريط IMDB، أيقونة التقييم (1/2) |
| `WatchingRow.gd` | صفحة الرئيسية في `home_screen.dart` | بطاقة آخر لعبة |
| `HomeScreen.gd/.tscn` | `lib/home_screen.dart` | صفحتان (رئيسية/شبكة)، انزلاق 0.4 ث، استعادة موضع التمرير، نافذة "قيد التطوير"، فحص التحديث (forced/optional) |
| `DetailsScreen.gd/.tscn` | `lib/details_screen.dart` | كاروسيل 1–3 صفحات، تقييمات، وصف + سطر الاعتماد، طاقم، تشغيل بخصم نقطة |
| `GameScreen.gd` + `GameWebView.gd` + إضافة KhayalWebView | `lib/game_screen.dart` | `webview_flutter`: https فقط، بلا جسر JS، نفس الموقع فقط، بلا تجاوز SSL |
| `SettingsScreen.gd/.tscn` | `lib/settings_screen.dart` | النقاط، تواصل، مشاركة (نسخ للحافظة)، ملاحظات، إعلان مكافأة |
| `AudioPlayer.gd` + `PlaylistScreen.gd` | `lib/audio_player_screen.dart` | `audioplayers`: تلاشي 0.4 ث، بحث بصمت 0.1 ث، 3 أوضاع، قائمة التشغيل |
| `LoadingScreen.gd` | `lib/loading_screen.dart` | 15 جملة، حد أدنى 3.5 ث، شريط ناعم |
| الألوان/التدرجات من `.tscn` | `lib/colors.dart` | منقولة حرفياً (GradientTexture2D: خطي/شعاعي بإحداثيات UV) |
| أبعاد 1080×1920 | `lib/design.dart` | كل الشاشات تُرسم على لوحة عرضها 1080 وتُكبَّر لعرض الجهاز |

## ما لم يُنقل (وسببه)
- `DebugConsole.gd`: أداة تطوير فقط.
- `AspectRatio.gd`: غير مستخدم (كان يطلب أذونات فيديو لا حاجة لها).
- `BackgroundFit.gd`, `PullIconDraw.gd`: وظيفتهما مدمجة في الودجات أعلاه.
- `LikeBtn.gd`: غير مستخدم في أي مشهد.
- زر `AdBtn` في الصفحة الرئيسية كان غير مرئي بالأصل؛ الإعلان متاح من الإعدادات.

## إضافات صغيرة (لم تكن بالأصل)
- زر رجوع في الإعدادات (الأصل كان يعتمد على رجوع النظام).
- أيقونة مشغّل الصوت (`a1w`) في عمود التبويبات (كانت بلا صورة بالمشهد).
- وضع "عشوائي" في مشغّل الصوت يعمل فعلاً (كان لا يفعل شيئاً).
- أيقونتا السابق/التالي: مثلث تشغيل (كانتا تعرضان أيقونة الإيقاف).
- عنوان/وسوم/سنة اللعبة تُملأ من JSON (كانت نصوصاً ثابتة في الأصل).
- نصوص صغيرة (IMDB / خيال / الجمهور) على مربعات التقييم.
- السحب الأفقي للتنقل بين صفحات التفاصيل.
