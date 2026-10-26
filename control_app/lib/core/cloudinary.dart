import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'store.dart';

class CloudinaryException implements Exception {
  final String message;
  CloudinaryException(this.message);
  @override
  String toString() => message;
}

class CloudImage {
  final String url;
  final String publicId;
  CloudImage(this.url, this.publicId);
}

/// رفع موقّع إلى Cloudinary وبناء روابط التحويل (مثل CloudinaryManager.gd).
class Cloudinary {
  Cloudinary._();
  static const _api = 'https://api.cloudinary.com/v1_1';

  static void _need() {
    if (!Store.hasCloudinary) {
      throw CloudinaryException('أدخل إعدادات Cloudinary أولاً (الإعدادات).');
    }
  }

  static String _sign(Map<String, String> params) {
    final keys = params.keys.where((k) => !const ['file', 'cloud_name', 'resource_type', 'api_key', 'signature'].contains(k)).toList()
      ..sort();
    final parts = <String>[];
    for (final k in keys) {
      final v = params[k] ?? '';
      if (v.isNotEmpty) parts.add('$k=$v');
    }
    return sha1.convert(utf8.encode(parts.join('&') + Store.clSecret)).toString();
  }

  static CloudImage _parse(http.Response r) {
    dynamic j;
    try {
      j = jsonDecode(r.body);
    } catch (_) {}
    if (r.statusCode != 200 || j is! Map) {
      final msg = (j is Map && j['error'] is Map) ? j['error']['message'] : 'HTTP ${r.statusCode}';
      throw CloudinaryException('Cloudinary: $msg');
    }
    return CloudImage(j['secure_url'].toString(), j['public_id'].toString());
  }

  static Map<String, String> _signed(Map<String, String> extra) {
    final p = {...extra, 'timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString()};
    final sig = _sign(p);
    return {...p, 'api_key': Store.clKey, 'signature': sig};
  }

  /// رفع صورة من الجهاز.
  static Future<CloudImage> uploadBytes(Uint8List bytes, String fileName, {String folder = 'games'}) async {
    _need();
    final fields = _signed({'folder': folder});
    final req = http.MultipartRequest('POST', Uri.parse('$_api/${Store.clCloud}/image/upload'))
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
    final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 90)));
    return _parse(res);
  }

  /// رفع صورة من رابط (يُستخدم لخبز التحويلات وسحب صور خارجية).
  static Future<CloudImage> uploadRemote(String url, {String? publicId, String folder = 'games'}) async {
    _need();
    final fields = _signed({
      if (publicId != null) 'public_id': publicId else 'folder': folder,
    });
    final res = await http
        .post(Uri.parse('$_api/${Store.clCloud}/image/upload'), body: {...fields, 'file': url})
        .timeout(const Duration(seconds: 90));
    return _parse(res);
  }

  static Future<String> ping() async {
    _need();
    final auth = base64Encode(utf8.encode('${Store.clKey}:${Store.clSecret}'));
    final r = await http
        .get(Uri.parse('$_api/${Store.clCloud}/ping'), headers: {'Authorization': 'Basic $auth'})
        .timeout(const Duration(seconds: 30));
    if (r.statusCode == 200) return 'متصل ✓  ${Store.clCloud}';
    throw CloudinaryException('Cloudinary ${r.statusCode}: تحقق من Cloud name / Key / Secret');
  }

  static String buildUrl(String cloud, String publicId, String chain) =>
      'https://res.cloudinary.com/$cloud/image/upload/${chain.isEmpty ? '' : '$chain/'}$publicId';

  /// يستخرج (cloud, publicId) من رابط Cloudinary، أو null إن لم يكن كذلك.
  static ({String cloud, String publicId})? parseUrl(String url) {
    final m = RegExp(r'res\.cloudinary\.com/([^/]+)/image/upload/(.+)$').firstMatch(url);
    if (m == null) return null;
    final segs = m.group(2)!.split('?').first.split('/');
    var i = 0;
    while (i < segs.length - 1 &&
        (RegExp(r'^[a-z]{1,3}_[^/]*$').hasMatch(segs[i]) || segs[i].contains(','))) {
      i++;
    }
    if (i < segs.length - 1 && RegExp(r'^v\d+$').hasMatch(segs[i])) i++;
    var pid = segs.sublist(i).join('/');
    final dot = pid.lastIndexOf('.');
    if (dot > 0) pid = pid.substring(0, dot);
    return (cloud: m.group(1)!, publicId: Uri.decodeComponent(pid));
  }

  // سلاسل تحويل جاهزة
  static const poster = 'c_fill,g_auto,w_600,h_800';
  static const wide = 'c_fill,g_auto,w_1280,h_720';
  static const blur = 'e_blur:800';
  static const enhance = 'e_improve,e_auto_color,e_sharpen';
  static const removeBg = 'e_background_removal';
  static const blurredBackground = 'c_fill,g_auto,w_1080,h_1920/e_blur:800';
}
