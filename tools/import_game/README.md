# خط استيراد الألعاب (بلا ذكاء اصطناعي)

الاستخدام: Actions ← **Import game** ← Run workflow ← ضع رابط مستودع اللعبة.

## ما يفعله
1. يفحص رخصة المستودع (تُقبل: MIT, Apache-2.0, BSD-2/3, CC0, CC-BY-3/4, GPL-3.0, ISC, Zlib). غير ذلك = فشل.
2. ينسخ المستودع، ويبحث عن نسخة ويب جاهزة (docs/dist/build/www/…/index.html في الجذر). إن لم يجد يبني بـ `npm run build`.
3. ينظّف: يحذف وسوم إعلانات/تتبّع معروفة من ملفات HTML، ويحوّل المسارات المطلقة (`/assets/..`) إلى نسبية، ويحذف `.map`.
4. يتحقق: حد 25MB للملف، 18000 ملف، 150MB إجمالي.
5. يختبر في Chromium آلي (جوال): تحميل الصفحة، أخطاء الكونسول، الملفات المفقودة، هل الصفحة فارغة. ويلتقط لقطة شاشة.
6. يختار غلافاً (من ملفات اللعبة) أو يستخدم لقطة الشاشة.
7. ينشر اللعبة في مستودع الاستضافة `games/<slug>/` مع `LICENSE` و`SOURCE.txt`.
8. يسجّلها: في `data_games.json` إن اخترت auto_publish=yes **ونجح كل شيء بلا تحذيرات**، وإلا في `data_games_pending.json` (تظهر في تبويب "للمراجعة" بتطبيق المتحكم).

## الإعداد مرة واحدة
1. أنشئ مستودعاً عاماً للاستضافة، مثل `games-host`، وفيه ملف `README` فقط. اربطه بـ Cloudflare Pages (بلا أمر بناء، والمجلد الجذر `/`) أو فعّل GitHub Pages.
2. أنشئ Fine-grained token على GitHub بصلاحية **Contents: Read and write** على المستودعين: `games-host` و`FlowData_Core`.
3. في مستودع التطبيقين: Settings ← Secrets and variables ← Actions:
   - Secret: `PUBLISH_TOKEN` = التوكن
   - Variables: `HOST_REPO` = `اسمك/games-host` ، `HOST_BASE_URL` = رابط موقع الاستضافة بلا / في آخره (مثل `https://games-host.pages.dev`)
   - اختياري: `HOST_BRANCH` (main)، `DATA_REPO` (الافتراضي ayssersalhi-a11y/FlowData_Core)، `DATA_BRANCH`.

## حدوده
- لا يعالج مشاريع Unity/Godot المصدرية (يحتاج نسخة ويب جاهزة).
- إن لم يُكتشف مجلد الويب، أدخل `subdir`. وإن كان البناء غير عادي، أدخل `build_cmd`.
- رخصة الكود لا تغطي دائماً الصور والأصوات. راجعها قبل الاعتماد.
- أي لعبة تعتمد على مسارات مطلقة داخل JS قد لا تعمل من مجلد فرعي؛ يظهر ذلك في تحذيرات الاختبار.
