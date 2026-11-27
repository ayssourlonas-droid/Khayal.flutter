/// ثوابت الأفلام في تطبيق المتحكم (ملف مستقل عن consts.dart).
const filmsFile = 'data_films.json';

/// رخص الأفلام المسموحة للتطبيق المموَّل بالإعلانات: حرة فقط (NC وND مرفوضتان).
const allowedFilmLicenses = [
  'CC0-1.0',
  'CC-BY-4.0',
  'CC-BY-3.0',
  'CC-BY-SA-4.0',
  'CC-BY-SA-3.0',
  'PUBLIC-DOMAIN',
  'OWNED',
  'PARTNER',
];

/// لغات مسارات الصوت والترجمة (نفس رموز لغات واجهة خيال).
const filmLangs = {
  'ar': 'العربية',
  'en': 'English',
  'fr': 'Français',
  'es': 'Español',
  'pt': 'Português',
  'de': 'Deutsch',
  'ru': 'Русский',
  'tr': 'Türkçe',
  'zh-CN': '中文',
  'hi': 'हिन्दी',
};

/// قواعد ظهور الفيلم للاعبين (خيال لا يعيد فحصها: الفحص هنا قبل الرفع).
/// يرجع "" إذا كان الفيلم سليماً.
String validateFilm(Map<String, dynamic> item) {
  Map m(dynamic v) => v is Map ? v : {};
  final main = m(item['main_scene']);
  final d = m(item['details_scene']);
  if ((main['title_ar'] ?? '').toString().trim().isEmpty) return 'اسم الفيلم مفقود';
  if (!(d['video_url'] ?? '').toString().startsWith('https://')) return 'رابط الفيديو مفقود أو ليس https';
  if (!allowedFilmLicenses.contains((d['license'] ?? '').toString())) return 'رخصة غير مسموحة';
  if ((d['credit'] ?? '').toString().trim().isEmpty) return 'سطر الاعتماد (المنتج/الصانع) مفقود';
  if (!(d['source_url'] ?? '').toString().startsWith('http')) return 'رابط المصدر مفقود (دليل الرخصة)';
  if ((main['poster_url'] ?? '').toString().trim().isEmpty) return 'صورة الغلاف مفقودة';
  for (final key in ['audio_tracks', 'subtitle_tracks']) {
    final l = d[key];
    if (l is! List) continue;
    for (final t in l) {
      final tm = m(t);
      if (!(tm['url'] ?? '').toString().startsWith('https://')) return 'رابط مسار في $key ليس https';
      if ((tm['lang'] ?? '').toString().isEmpty) return 'لغة مسار في $key مفقودة';
    }
  }
  return '';
}
