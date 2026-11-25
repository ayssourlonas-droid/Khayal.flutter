
---
## قسم الأفلام (25 نوفمبر 2026) — يُلصق في آخر `docs/GUIDE.md`

**الهدف:** قسم أفلام مرخّصة في خيال بنفس تصميم الألعاب، يُدار كله من تطبيق المتحكم. الفحص الحقيقي للرخصة في المتحكم وخط الاستيراد، وتطبيق خيال لا يكرّره (كما مع الألعاب).

**الملفات (في `games_app/lib/`):**
| الملف | الدور |
|---|---|
| `film_data.dart` | `FilmLibrary` (فحص تقني: رابط فيديو https فقط) + `FilmState` (حالة الجلسة) + `FilmRepository` (ذاكرة ← قرص ← شبكة) + `FilmConfig.key` (بادئة `film_` للمفضلة والتخزين) |
| `film_card.dart` | بطاقة الفيلم (نسخة GameCard) |
| `film_home_feed.dart` | الرئيسية: تابع المشاهدة ← المفضلة ← فيلم اليوم ← اقتراحات |
| `film_home_screen.dart` | شاشة الأفلام الرئيسية (صفحتان: الرئيسية والشبكة) مع البحث والتصفية |
| `film_details_screen.dart` | صفحة التفاصيل (معرض / القصة / طاقم) |
تعديلات صغيرة على ملفات قديمة، موسومة بـ `[أفلام]`: `config.dart` (`Config.filmsJsonUrl`) و`home_screen.dart` (زر الانتقال لقسم الأفلام).

**البيانات:** `data_films.json` في `khayal-control` بنفس بنية الألعاب: `id` و`release_year` و`category_tags` و`main_scene{title_ar,title_en,poster_url,imdb_rating,app_rating,rating_icon_type}` و`details_scene{description,background_url,duration_min,video_url,source_url,license,license_url,credit,cast,special_items}`. الشرط الوحيد لظهور الفيلم في التطبيق: `video_url` يبدأ بـ `https://`.

**المفضلة وآخر فيلم:** مفاتيح الأفلام بادئتها `film_` (قائمة `fav_ids` المشتركة) و`last_film_id` منفصل، كي لا يتصادم رقم فيلم مع رقم لعبة.

**المشغّل:** `film_player_screen.dart` + `film_player_widgets.dart` على محرك media_kit (libmpv/FFmpeg) بنفس فكرة مشغّل جودوت: روابط https مباشرة، تحميل مسبق، شريط تقديم بمنطقة آمنة (10%)، نقر مزدوج للتقديم/الرجوع بمدة يختارها المستخدم (5–60 ثانية)، استئناف من آخر موضع (`film_pos_<id>`)، ترجمة خارجية (`details_scene.subtitle_url` بصيغة srt/vtt) أو مدمجة بمظهر قابل للتعديل، مسارات صوت، سرعة، ملء الشاشة. يفتح أفقياً ويعيد العمودي عند الخروج. زر التشغيل: إعلان بيني ثم المشغّل. الحزم في `pubspec.yaml` والتهيئة `MediaKit.ensureInitialized()` في `main.dart` (موسومة `[مشغل]`).

**لم يُجرَّب:** كود Dart لم يُترجَم في بيئة الكتابة (لا Flutter SDK)؛ يُفحص بـ `Check code`.

**قيود الاستضافة (من صفحة Cloudflare الرسمية، 19 نوفمبر 2026):** الملف الواحد في Pages حدّه 25 MiB، فلا يُرفع فيديو إلى `khayal-control`؛ يُخزَّن رابط مباشر خارجي (أو حاوية R2 عامة).

**مسارات منفصلة (صورة / صوت / ترجمة):** لتقليل الحجم، الفيديو يُرفع مرة واحدة **بلا صوت** (`video_url`)، وكل لغة صوت ملف مستقل `.m4a` أو `.opus` في `details_scene.audio_tracks: [{lang,title,url}]`، وكل ترجمة ملف `.srt` أو `.vtt` في `details_scene.subtitle_tracks: [{lang,title,url}]`. يختار المشغّل الصوت: آخر لغة اخترتها ثم لغة الواجهة ثم الأول، ويغيّره المستخدم من أيقونة الصوت في المشغّل (والترجمة كذلك، أول مرة بلا ترجمة). إن لم توجد `audio_tracks` يُستعمل صوت ملف الفيديو نفسه، و`subtitle_url` القديم ما زال مقبولاً كترجمة واحدة. الروابط غير https تُهمل.
