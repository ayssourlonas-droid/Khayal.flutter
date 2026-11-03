# قوالب مستودع الاستضافة (games-host)

انسخ مجلد `legal/` إلى **جذر** مستودع الاستضافة (الذي تقرأ منه Cloudflare Pages)، ثم عدّل `terms.html` و`privacy.html` (استبدل ما بين [ ]).

- `legal/terms.html` و`legal/privacy.html`: تكتبهما أنت (لا يلمسهما الاستيراد).
- `legal/credits.html` (+`credits.json`): يولّدهما الاستيراد تلقائياً بعد كل لعبة جديدة. لا تعدّلهما يدوياً.

بعد النشر ضع الروابط في `version.json` (في FlowData_Core):
```
"terms_url":   "https://<موقعك>.pages.dev/legal/terms.html",
"privacy_url": "https://<موقعك>.pages.dev/legal/privacy.html",
"credits_url": "https://<موقعك>.pages.dev/legal/credits.html"
```
رابط الخصوصية نفسه تضعه أيضاً في Google Play Console.
