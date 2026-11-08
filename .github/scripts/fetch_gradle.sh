#!/usr/bin/env bash
# يحمّل Gradle مسبقاً مع إعادة محاولة وتدرّج في الانتظار، ثم يوجّه الـ wrapper إلى الملف المحلي.
# سبب وجوده: تحميل الـ wrapper المباشر من github.com يفشل أحياناً بخطأ 504 فيسقط البناء كله.
# لا يُفشل البناء إن تعذّر التحميل: يترك الإعداد كما هو ويعود الـ wrapper لسلوكه الافتراضي.
# الاستعمال: fetch_gradle.sh <مجلد android>
set -u
VER=8.9
PROP="${1:-android}/gradle/wrapper/gradle-wrapper.properties"
OUT="${RUNNER_TEMP:-/tmp}/gradle-$VER-bin.zip"
URLS=("https://services.gradle.org/distributions/gradle-$VER-bin.zip" "https://downloads.gradle.org/distributions/gradle-$VER-bin.zip")

if [ ! -f "$PROP" ]; then echo "لا يوجد $PROP: تخطي"; exit 0; fi

valid() { python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); sys.exit(1 if z.testzip() else 0)" "$1" 2>/dev/null; }

ok=0
if [ -f "$OUT" ] && valid "$OUT"; then
  echo "Gradle موجود مسبقاً (من الكاش): $OUT"; ok=1
else
  for attempt in 1 2 3 4 5 6; do
    for u in "${URLS[@]}"; do
      echo "محاولة $attempt: $u"
      rm -f "$OUT"
      if curl -fL --connect-timeout 20 --max-time 240 -o "$OUT" "$u" && valid "$OUT"; then ok=1; break 2; fi
    done
    [ "$attempt" -lt 6 ] && { echo "فشل؛ انتظار $((attempt*20)) ثانية"; sleep $((attempt*20)); }
  done
fi

if [ "$ok" = 1 ]; then
  sed -i "s|^distributionUrl=.*|distributionUrl=file://$OUT|" "$PROP"
  echo "تم توجيه wrapper إلى الملف المحلي:"; grep '^distributionUrl' "$PROP"
else
  echo "::warning title=Gradle::تعذّر تحميل Gradle مسبقاً؛ سيحاول wrapper التحميل بنفسه"
  rm -f "$OUT"
fi
exit 0
