#!/usr/bin/env python3
"""
يُشغَّل في CI بعد `flutter create` ليضبط مجلد android المولَّد:
  - الحد الأدنى SDK = 24 
  - أذونات INTERNET و ACCESS_NETWORK_STATE
  - اسم التطبيق
  - التوقيع من key.properties إن وُجد (وإلا توقيع debug حتى يمكن تثبيت الـ APK)
يعمل مع build.gradle (Groovy) و build.gradle.kts.
"""
import os
import re
import sys

APP_NAME = os.environ.get("APP_NAME") or "متحكم الألعاب"

root = sys.argv[1] if len(sys.argv) > 1 else "."
app_dir = os.path.join(root, "android", "app")

# ───── AndroidManifest ─────
mp = os.path.join(app_dir, "src", "main", "AndroidManifest.xml")
m = open(mp, encoding="utf-8").read()
perms = ""
for p in ("android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE"):
    if p not in m:
        perms += f'    <uses-permission android:name="{p}"/>\n'
if perms:
    m = re.sub(r"(<manifest[^>]*>\s*\n)", lambda x: x.group(1) + perms, m, count=1)
m = re.sub(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', m, count=1)
if "usesCleartextTraffic" not in m:
    m = m.replace("<application", '<application\n        android:usesCleartextTraffic="false"', 1)
open(mp, "w", encoding="utf-8").write(m)

# ───── build.gradle(.kts) ─────
kts = os.path.exists(os.path.join(app_dir, "build.gradle.kts"))
gp = os.path.join(app_dir, "build.gradle.kts" if kts else "build.gradle")
g = open(gp, encoding="utf-8").read()

g = re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", "minSdk = 24" if kts else "minSdkVersion 24", g)
g = re.sub(r"minSdk\s*=\s*\d+", "minSdk = 24", g) if kts else re.sub(r"minSdkVersion\s+\d+", "minSdkVersion 24", g)

if "keystoreProperties" not in g:
    if kts:
        header = (
            "import java.util.Properties\nimport java.io.FileInputStream\n\n"
            "val keystoreProperties = Properties()\n"
            'val keystorePropertiesFile = rootProject.file("key.properties")\n'
            "if (keystorePropertiesFile.exists()) {\n"
            "    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n}\n\n"
        )
        signing = (
            "    signingConfigs {\n"
            '        create("release") {\n'
            '            if (keystorePropertiesFile.exists()) {\n'
            '                keyAlias = keystoreProperties["keyAlias"] as String\n'
            '                keyPassword = keystoreProperties["keyPassword"] as String\n'
            '                storeFile = file(keystoreProperties["storeFile"] as String)\n'
            '                storePassword = keystoreProperties["storePassword"] as String\n'
            "            }\n        }\n    }\n\n"
        )
        g = header + g
        g = re.sub(r"(\n\s*buildTypes\s*\{)", "\n" + signing.rstrip("\n") + r"\1", g, count=1)
        g = re.sub(
            r"signingConfig\s*=\s*signingConfigs\.(getByName\(\"debug\"\)|debug)",
            'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")',
            g,
        )
    else:
        header = (
            "def keystoreProperties = new Properties()\n"
            "def keystorePropertiesFile = rootProject.file('key.properties')\n"
            "if (keystorePropertiesFile.exists()) {\n"
            "    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n}\n\n"
        )
        signing = (
            "    signingConfigs {\n"
            "        release {\n"
            "            if (keystorePropertiesFile.exists()) {\n"
            "                keyAlias keystoreProperties['keyAlias']\n"
            "                keyPassword keystoreProperties['keyPassword']\n"
            "                storeFile file(keystoreProperties['storeFile'])\n"
            "                storePassword keystoreProperties['storePassword']\n"
            "            }\n        }\n    }\n\n"
        )
        # يجب أن يسبق الكتلة plugins {}؟ لا: def يمكن أن يأتي بعدها
        g = re.sub(r"(\nandroid\s*\{)", "\n" + header.rstrip("\n") + r"\1", g, count=1)
        g = re.sub(r"(\n\s*buildTypes\s*\{)", "\n" + signing.rstrip("\n") + r"\1", g, count=1)
        g = re.sub(
            r"signingConfig\s*=?\s*signingConfigs\.debug",
            "signingConfig keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug",
            g,
        )

open(gp, "w", encoding="utf-8").write(g)
print("android patched:", gp)

# ───── رفع إصدارات أدوات البناء (مكتبات حديثة مثل androidx.webkit 1.14 تتطلب AGP أحدث و compileSdk 35) ─────
for name in ("settings.gradle", "settings.gradle.kts"):
    sp = os.path.join(root, "android", name)
    if os.path.exists(sp):
        s = open(sp, encoding="utf-8").read()
        s = re.sub(r'(com\.android\.application"\s*\)?\s*version\s*"?)[\d.]+', r"\g<1>8.7.3", s)
        s = re.sub(r'(org\.jetbrains\.kotlin\.android"\s*\)?\s*version\s*"?)[\d.]+', r"\g<1>1.9.24", s)
        open(sp, "w", encoding="utf-8").write(s)
        print("patched", sp)

wp = os.path.join(root, "android", "gradle", "wrapper", "gradle-wrapper.properties")
if os.path.exists(wp):
    w = open(wp, encoding="utf-8").read()
    w = re.sub(r"gradle-[\d.]+-(all|bin)\.zip", "gradle-8.9-all.zip", w)
    open(wp, "w", encoding="utf-8").write(w)
    print("patched", wp)

g = open(gp, encoding="utf-8").read()
g = re.sub(r"compileSdk(Version)?\s*=?\s*flutter\.compileSdkVersion", "compileSdk = 35" if kts else "compileSdk 35", g)
open(gp, "w", encoding="utf-8").write(g)
