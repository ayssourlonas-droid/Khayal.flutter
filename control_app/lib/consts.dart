/// مطابق لقائمة التراخيص في تطبيق اللاعبين وفي Add_Film.gd القديم.
const allowedLicenses = [
  'MIT',
  'Apache-2.0',
  'BSD-2-Clause',
  'BSD-3-Clause',
  'CC0-1.0',
  'CC-BY-4.0',
  'CC-BY-3.0',
  'GPL-3.0',
  'GPL-2.0',
  'LGPL-3.0',
  'LGPL-2.1',
  'MPL-2.0',
  'CC-BY-SA-4.0',
  'ISC',
  'Zlib',
  'Unlicense',
  '0BSD',
  'BSL-1.0',
  'WTFPL',
  'Artistic-2.0',
  'AFL-3.0',
  'OWNED',
  'PARTNER',
];

const orientations = ['portrait', 'landscape', 'both'];

const gamesFile = 'data_games.json';
const featuredFile = 'data_games_featured.json';
const pendingFile = 'data_games_pending.json';
const versionFile = 'version.json';

const defaultOwner = 'ayssourlonas-droid';
const defaultRepo = 'khayal-control';
const defaultBranch = 'main';

/// نفس قواعد GameLibrary في تطبيق اللاعبين (+ صورة الغلاف إلزامية قبل الرفع).
/// يرجع "" إذا كانت اللعبة سليمة.
String validateGame(Map<String, dynamic> item) {
  Map m(dynamic v) => v is Map ? v : {};
  final main = m(item['main_scene']);
  final d = m(item['details_scene']);
  if ((main['title_ar'] ?? '').toString().trim().isEmpty) return 'اسم اللعبة مفقود';
  if (!(d['play_url'] ?? '').toString().startsWith('https://')) {
    return 'رابط اللعبة مفقود أو ليس https';
  }
  if (!allowedLicenses.contains((d['license'] ?? '').toString())) {
    return 'رخصة غير مسموحة';
  }
  if ((d['developer'] ?? '').toString().trim().isEmpty) return 'اسم المطوّر مفقود';
  if (!(d['source_url'] ?? '').toString().startsWith('http')) {
    return 'رابط المصدر مفقود (دليل الرخصة)';
  }
  if ((main['poster_url'] ?? '').toString().trim().isEmpty) return 'صورة الغلاف مفقودة';
  return '';
}
