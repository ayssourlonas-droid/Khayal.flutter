import 'dart:convert';

import 'package:http/http.dart' as http;

import 'film_consts.dart';
import 'license_detect.dart';

/// فيلم مرشّح من مصدر مفتوح، مع رخصته المكتشفة.
class FilmCandidate {
  final String source; // archive | commons
  final String sourceId;
  final String title;
  final String creator;
  final String year;
  final String description;
  final String thumb;
  final String pageUrl;
  final String licenseRaw; // النص/الرابط كما جاء من المصدر
  final String licenseUrl;
  final LicenseDetection license;
  String videoUrl; // قد يُحلّ لاحقاً (archive)
  List<Map<String, String>> subtitles; // [{lang,url}] إن وُجدت

  FilmCandidate({
    required this.source,
    required this.sourceId,
    required this.title,
    required this.creator,
    required this.year,
    required this.description,
    required this.thumb,
    required this.pageUrl,
    required this.licenseRaw,
    required this.licenseUrl,
    required this.license,
    this.videoUrl = '',
    this.subtitles = const [],
  });

  /// سجل أولي للنموذج (يُكمله المستخدم: الاسم العربي، الغلاف، التصنيفات ...).
  Map<String, dynamic> toPrefill() => {
        'release_year': year,
        'category_tags': <String>[],
        'main_scene': {'title_ar': '', 'title_en': title, 'poster_url': thumb, 'app_rating': 0.0},
        'details_scene': {
          'description': description,
          'video_url': videoUrl,
          'credit': creator,
          'license': license.id ?? allowedFilmLicenses.first,
          'license_url': licenseUrl,
          'source_url': pageUrl,
          'audio_tracks': <Map<String, String>>[],
          'subtitle_tracks': subtitles,
        },
      };
}

/// بحث في مصدرين مفتوحين بلا مفتاح: Internet Archive وWikimedia Commons.
/// لا يرجع إلا نتائج لها رخصة مكتوبة في بياناتها، ثم يُحكم عليها بـ [LicenseDetector].
class FilmSearchApi {
  FilmSearchApi._();
  static const _timeout = Duration(seconds: 25);
  static const _ua = {'User-Agent': 'khayal-control/1.0 (film license search)'};

  static String _strip(String s) =>
      s.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll('&amp;', '&').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _first(dynamic v) {
    if (v is List) return v.isEmpty ? '' : '${v.first}';
    return v == null ? '' : '$v';
  }

  // ───────────── Internet Archive ─────────────
  static Future<List<FilmCandidate>> archive(String query, {int page = 1}) async {
    final q = query.trim().isEmpty ? '' : '(${query.trim()}) AND ';
    final uri = Uri.https('archive.org', '/advancedsearch.php', {
      'q': '${q}mediatype:movies AND (licenseurl:*creativecommons.org* OR licenseurl:*publicdomain*)',
      'fl[]': ['identifier', 'title', 'creator', 'year', 'description', 'licenseurl'],
      'sort[]': 'downloads desc',
      'rows': '30',
      'page': '$page',
      'output': 'json',
    });
    final r = await http.get(uri, headers: _ua).timeout(_timeout);
    if (r.statusCode != 200) throw Exception('Internet Archive ${r.statusCode}');
    final docs = (jsonDecode(utf8.decode(r.bodyBytes))['response']?['docs'] as List?) ?? [];
    final out = <FilmCandidate>[];
    for (final d in docs) {
      if (d is! Map) continue;
      final id = _first(d['identifier']);
      if (id.isEmpty) continue;
      final lic = _first(d['licenseurl']);
      out.add(FilmCandidate(
        source: 'archive',
        sourceId: id,
        title: _strip(_first(d['title'])),
        creator: _strip(_first(d['creator'])),
        year: _first(d['year']),
        description: _strip(_first(d['description'])),
        thumb: 'https://archive.org/services/img/$id',
        pageUrl: 'https://archive.org/details/$id',
        licenseRaw: lic,
        licenseUrl: lic.startsWith('http') ? lic : '',
        license: LicenseDetector.detect(lic),
      ));
    }
    return out;
  }

  /// يحلّ رابط الفيديو المباشر (أفضل mp4/webm/ogv) وملفات الترجمة من metadata الأرشيف.
  static Future<void> resolveArchive(FilmCandidate c) async {
    final r = await http.get(Uri.https('archive.org', '/metadata/${c.sourceId}'), headers: _ua).timeout(_timeout);
    if (r.statusCode != 200) throw Exception('Internet Archive ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final files = (j['files'] as List?) ?? [];
    int size(Map f) => int.tryParse('${f['size'] ?? 0}') ?? 0;
    int rank(Map f) {
      final n = '${f['name']}'.toLowerCase();
      final fmt = '${f['format']}'.toLowerCase();
      if (n.endsWith('.mp4') && (fmt.contains('h.264') || fmt.contains('mpeg4'))) return 3;
      if (n.endsWith('.mp4')) return 2;
      if (n.endsWith('.webm')) return 1;
      if (n.endsWith('.ogv')) return 0;
      return -1;
    }

    final vids = [for (final f in files) if (f is Map && rank(f) >= 0) f]
      ..sort((a, b) {
        final c1 = rank(b).compareTo(rank(a));
        return c1 != 0 ? c1 : size(b).compareTo(size(a));
      });
    if (vids.isNotEmpty) {
      c.videoUrl = Uri.https('archive.org', '/download/${c.sourceId}/${vids.first['name']}').toString();
    }
    final subs = <Map<String, String>>[];
    for (final f in files) {
      if (f is! Map) continue;
      final n = '${f['name']}';
      final l = n.toLowerCase();
      if (!(l.endsWith('.srt') || l.endsWith('.vtt'))) continue;
      final m = RegExp(r'[._-](ar|en|fr|es|pt|de|ru|tr|hi|zh)[._-]').firstMatch(l);
      subs.add({
        'lang': m?.group(1) ?? 'en',
        'title': '',
        'url': Uri.https('archive.org', '/download/${c.sourceId}/$n').toString(),
      });
    }
    c.subtitles = subs;
  }

  // ───────────── Wikimedia Commons ─────────────
  static Future<List<FilmCandidate>> commons(String query) async {
    final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query',
      'generator': 'search',
      'gsrnamespace': '6',
      'gsrsearch': '${query.trim()} filetype:video',
      'gsrlimit': '30',
      'prop': 'imageinfo',
      'iiprop': 'url|mime|size|extmetadata',
      'iiurlwidth': '400',
      'iiextmetadatafilter': 'LicenseShortName|LicenseUrl|Artist|ImageDescription|DateTimeOriginal|ObjectName',
      'format': 'json',
    });
    final r = await http.get(uri, headers: _ua).timeout(_timeout);
    if (r.statusCode != 200) throw Exception('Wikimedia Commons ${r.statusCode}');
    final pages = (jsonDecode(utf8.decode(r.bodyBytes))['query']?['pages'] as Map?) ?? {};
    final out = <FilmCandidate>[];
    for (final p in pages.values) {
      if (p is! Map) continue;
      final info = (p['imageinfo'] as List?)?.firstOrNull;
      if (info is! Map) continue;
      final ext = (info['extmetadata'] as Map?) ?? {};
      String v(String k) => ext[k] is Map ? '${ext[k]['value'] ?? ''}' : '';
      final short = v('LicenseShortName');
      final url = v('LicenseUrl');
      final title = '${p['title'] ?? ''}'.replaceFirst('File:', '').replaceAll(RegExp(r'\.\w+$'), '').replaceAll('_', ' ');
      final date = v('DateTimeOriginal');
      out.add(FilmCandidate(
        source: 'commons',
        sourceId: '${p['pageid'] ?? p['title']}',
        title: _strip(v('ObjectName').isEmpty ? title : v('ObjectName')),
        creator: _strip(v('Artist')),
        year: RegExp(r'\d{4}').firstMatch(date)?.group(0) ?? '',
        description: _strip(v('ImageDescription')),
        thumb: '${info['thumburl'] ?? ''}',
        pageUrl: 'https://commons.wikimedia.org/wiki/${Uri.encodeComponent('${p['title']}'.replaceAll(' ', '_'))}',
        licenseRaw: '$short $url',
        licenseUrl: url,
        license: LicenseDetector.detect('$url $short'),
        videoUrl: '${info['url'] ?? ''}',
      ));
    }
    return out;
  }
}
