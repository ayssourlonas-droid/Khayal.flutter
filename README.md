# مستودع التطبيقين

- `games_app/` تطبيق اللاعبين (خيال): الكود والشيدرات مباشرة تحت `lib/`، والوسائط في `assets/images` و`assets/audio`.
- `control_app/` تطبيق التحكم (Game Control): كل الكود مباشرة تحت `lib/`.
- `tools/import_game/` خط استيراد الألعاب (GitHub Actions)، و`tools/health_check.py` فحص صحة الألعاب.
- `host_template/` قوالب مستودع الاستضافة: الصفحات القانونية و Worker العزل والإحصاء.
- `.github/workflows/` : `build.yml` و`import-game.yml` و`health-check.yml`.

## ما يُبنى
البناء تلقائي عند أي تحديث، ويحدده **السطر الأول** من `BUILD_TARGET.txt`:
- `1` = خيال فقط، `2` = المتحكم فقط، `12` أو `21` = الاثنان.
- أي شيء آخر (لا 1 ولا 2) = لا يبني شيئاً.
- ما بعد `//` أو `#` تعليق.
