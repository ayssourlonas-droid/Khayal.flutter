# GameHub (خيال) — Flutter

تطبيق ألعاب ويب مرخّصة، معاد كتابته بالكامل من Godot إلى Flutter بنفس الميزات والألوان والزينات.
انظر `docs/MAPPING.md` لجدول التحويل الكامل.

## البناء على GitHub (بدون Flutter على جهازك)
1. أنشئ مستودعاً جديداً وارفع محتويات هذا المجلد كما هي (المجلد `android/` غير موجود عمداً: يُولَّد تلقائياً).
2. من تبويب **Actions** شغّل **Build Android APK** (أو ادفع إلى `main`).
3. حين ينجح، حمّل الملف من **Artifacts**: `gamehub-apk` (للتثبيت المباشر) و`gamehub-aab` (للمتجر).

### اختياري
| الإعداد | أين | الغرض |
|---|---|---|
| `ADMOB_APP_ID` | Settings → Variables → Actions | معرّف تطبيق AdMob (`ca-app-pub-…~…`). بدونه يُستعمل معرّف اختبار Google |
| `APP_NAME` | Variables | اسم التطبيق (الافتراضي khayal) |
| `KEYSTORE_BASE64` | Secrets | `base64 -w0 lamoushi.keystore.jks` |
| `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` | Secrets | بيانات التوقيع |

بدون الأسرار يُبنى APK بتوقيع debug (يُثبَّت للتجربة، لا يصلح للمتجر).

## قبل النشر
- ضع معرّفات الوحدات الحقيقية في `lib/core/config.dart` (`realBannerId`, `realRewardedId`) ثم `useTestAds = false`.
- **لا تضع الـ keystore في المستودع** (`.gitignore` يمنعه).
- غيّر في `FlowData_Core`: `version.json` يجب أن يحوي `latest_version` و`download_url` (اختياري: `update_mode`, `whatsapp_url`, `support_email`, `app_page_url`, `feedback_url`).
- ملفات الألعاب يجب أن تكون على نطاق واحد https (رابط `play_url`)، لأن الـ WebView يمنع الانتقال لنطاق آخر.

## إن فشل البناء
انسخ سطور الخطأ (الأحمر) من سجل الخطوة الفاشلة وأرسلها لي. هذا الكود لم يُترجَم في بيئتي (لا يوجد Flutter SDK هناك)، فمتوقع بعض أخطاء الصياغة الصغيرة بالمحاولة الأولى.
