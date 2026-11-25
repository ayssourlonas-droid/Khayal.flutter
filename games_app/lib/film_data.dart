import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// بيانات الأفلام: الإعدادات + فحص السلامة + حالة الجلسة + التحميل (ذاكرة ← قرص ← شبكة).
/// ملف مستقل عن game_library / app_state / data_repository. الرابط في config.dart (Config.filmsJsonUrl).

class FilmConfig {
  FilmConfig._();

  /// بادئة مفاتيح الأفلام في المفضلة والتخزين المحلي (كي لا تتصادم أرقامها مع أرقام الألعاب).
  static String key(Map<String, dynamic> film) => 'film_${film['id'] ?? ''}';
}

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// فحص سلامة بيانات الفيلم تقنياً فقط. فحص الرخصة والاعتماد يتم في تطبيق «متحكم» قبل الاعتماد،
/// فلا يكرّره هذا التطبيق (مثل GameLibrary للألعاب). لا يظهر فيلم إلا إذا كان له رابط فيديو https.
class FilmLibrary {
  FilmLibrary._();

  static String licenseOf(Map<String, dynamic> film) =>
      (_map(film['details_scene'])['license'] ?? '').toString().trim();

  static String creditOf(Map<String, dynamic> film) {
    final d = _map(film['details_scene']);
    return (d['credit'] ?? d['developer'] ?? '').toString().trim();
  }

  /// يرجع "" إذا كان الفيلم سليماً، وإلا نص يشرح السبب.
  static String validate(Map<String, dynamic> film) {
    final d = _map(film['details_scene']);
    final videoUrl = (d['video_url'] ?? '').toString().trim();
    if (!videoUrl.startsWith('https://')) return 'رابط الفيديو مفقود أو ليس https';
    return '';
  }

  static List<Map<String, dynamic>> filterValid(List<dynamic> list) {
    final out = <Map<String, dynamic>>[];
    for (final f in list) {
      if (f is! Map) continue;
      final film = Map<String, dynamic>.from(f);
      final why = validate(film);
      if (why.isEmpty) {
        out.add(film);
      } else {
        final title = _map(film['main_scene'])['title_ar'] ?? '?';
        // ignore: avoid_print
        print("⛔ [FilmLibrary] استُبعد الفيلم '$title' — $why");
      }
    }
    return out;
  }

  /// سطر الاعتماد المعروض تحت القصة (عرض فقط، لا يمنع ظهور الفيلم). فارغ إن لم تُكتب بيانات.
  static String creditLine(Map<String, dynamic> film) {
    final credit = creditOf(film);
    final lic = licenseOf(film).replaceAll('-', ' ');
    return [
      if (credit.isNotEmpty) 'الإنتاج: $credit',
      if (lic.isNotEmpty) 'الرخصة: $lic',
    ].join('  •  ');
  }
}

/// مسار منفصل (صوت أو ترجمة): لغته واسمه ورابطه. الفيديو صورة فقط، والأصوات والترجمات ملفات مستقلة.
class FilmTrack {
  final String lang; // رمز اللغة: ar, en, fr ...
  final String title;
  final String url;
  const FilmTrack(this.lang, this.title, this.url);

  static List<FilmTrack> parse(dynamic v) {
    if (v is! List) return const [];
    final out = <FilmTrack>[];
    for (final e in v) {
      if (e is! Map) continue;
      final url = (e['url'] ?? '').toString().trim();
      if (!url.startsWith('https://')) continue;
      final lang = (e['lang'] ?? '').toString().trim();
      out.add(FilmTrack(lang, (e['title'] ?? '').toString().trim(), url));
    }
    return out;
  }
}

extension FilmTracks on Map<String, dynamic> {
  Map<String, dynamic> get _d => this['details_scene'] is Map ? Map<String, dynamic>.from(this['details_scene'] as Map) : {};

  /// الأصوات المنفصلة (details_scene.audio_tracks).
  List<FilmTrack> get audioTracks => FilmTrack.parse(_d['audio_tracks']);

  /// الترجمات المنفصلة (details_scene.subtitle_tracks) + القديم subtitle_url كمسار واحد.
  List<FilmTrack> get subtitleTracks {
    final l = FilmTrack.parse(_d['subtitle_tracks']).toList();
    final old = (_d['subtitle_url'] ?? '').toString().trim();
    if (l.isEmpty && old.startsWith('https://')) l.add(FilmTrack('', '', old));
    return l;
  }
}

/// حالة الجلسة (تقابل AppState لكن للأفلام فقط).
class FilmState {
  FilmState._();

  static Map<String, dynamic> currentFilm = {};
  static Uint8List? currentPoster;
  static Uint8List? currentBackground;

  static int lastPageIndex = 0; // 0 = الرئيسية، 1 = الشبكة
  static final Map<int, double> pageScrollPositions = {};

  static List<Map<String, dynamic>> cachedList = [];

  static Map<String, dynamic>? lastWatched;
  static String currentVideoUrl = '';
}

/// ذاكرة ← قرص ← شبكة، مع تحديث صامت بالخلفية (نفس منطق DataRepository للألعاب).
class FilmRepository {
  FilmRepository._();

  static const _timeout = Duration(seconds: 15);
  static const _diskKey = 'cache_list_films';
  static const _lastKey = 'last_film_id';

  /// يستدعي [onData] فوراً بما في الذاكرة/القرص (إن وُجد) ثم بنتيجة الشبكة إن اختلفت.
  /// يرجع true إن وصلت بيانات (من أي مصدر).
  static Future<bool> load(
    void Function(List<Map<String, dynamic>> films, {required bool fromNetwork}) onData, {
    bool forceNetwork = false,
  }) async {
    var delivered = false;
    String? shownSig;

    if (!forceNetwork) {
      if (FilmState.cachedList.isNotEmpty) {
        onData(FilmState.cachedList, fromNetwork: false);
        shownSig = jsonEncode(FilmState.cachedList);
        delivered = true;
      } else {
        final disk = await _readDisk();
        if (disk != null && disk.isNotEmpty) {
          FilmState.cachedList = disk;
          onData(disk, fromNetwork: false);
          shownSig = jsonEncode(disk);
          delivered = true;
        }
      }
    }

    final fresh = await _fetchNetwork();
    if (fresh != null) {
      FilmState.cachedList = fresh;
      _writeDisk(fresh);
      if (jsonEncode(fresh) != shownSig) onData(fresh, fromNetwork: true);
      delivered = true;
    }
    return delivered;
  }

  static Future<List<Map<String, dynamic>>?> _fetchNetwork() async {
    try {
      final url = '${Config.filmsJsonUrl}?v=${DateTime.now().millisecondsSinceEpoch}';
      final res = await http.get(Uri.parse(url)).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! List) return null; // يجب أن يكون JSON مصفوفة
      return FilmLibrary.filterValid(data);
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>?> _readDisk() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_diskKey);
      if (s == null) return null;
      final data = jsonDecode(s);
      if (data is! List) return null;
      // إعادة التحقق عند القراءة: قواعد الرخص قد تتغير بين الإصدارات
      return FilmLibrary.filterValid(data);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeDisk(List<Map<String, dynamic>> list) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_diskKey, jsonEncode(list));
    } catch (_) {}
  }

  /// آخر فيلم فُتح (محفوظ على الجهاز، مفتاح مستقل عن «آخر لعبة»).
  static Future<String> readLastId() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(_lastKey) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> saveLastId(String id) async {
    if (id.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_lastKey, id);
    } catch (_) {}
  }
}
