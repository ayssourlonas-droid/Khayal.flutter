import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:pinenacl/api.dart';
import 'package:pinenacl/x25519.dart';
import 'github.dart' show GhException;
import 'store.dart';

/// يرسل إعدادات الذكاء الاصطناعي إلى أسرار GitHub (مشفّرة) في مستودع المشاريع.
/// التوكن يحتاج صلاحية Secrets: Read and write على ذلك المستودع.
class SecretsApi {
  SecretsApi._();

  static Map<String, String> _h() {
    final t = Store.ghToken;
    return {
      'Authorization': t.startsWith('ghp_') ? 'token $t' : 'Bearer $t',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'gamehub-control',
      'Content-Type': 'application/json',
    };
  }

  static String get _base => '/repos/${Store.acOwner}/${Store.acRepo}/actions/secrets';

  static Future<String> sendAi() async {
    if (Store.ghToken.isEmpty) throw GhException('أدخل توكن GitHub أولاً.');
    if (Store.aiKey.isEmpty || Store.aiEndpoint.isEmpty || Store.aiModel.isEmpty) {
      throw GhException('املأ المفتاح والرابط واسم النموذج واحفظ أولاً.');
    }
    final pk = await http.get(Uri.https('api.github.com', '$_base/public-key'), headers: _h());
    if (pk.statusCode != 200) {
      throw GhException('تعذّر جلب مفتاح التشفير (${pk.statusCode}). تأكد أن التوكن يملك Secrets: Read and write على ${Store.acOwner}/${Store.acRepo}.');
    }
    final j = jsonDecode(pk.body);
    final keyId = j['key_id'].toString();
    final box = SealedBox(PublicKey(Uint8List.fromList(base64Decode(j['key'].toString()))));
    final values = {
      'AI_API_KEY': Store.aiKey,
      'AI_ENDPOINT': Store.aiEndpoint,
      'AI_MODEL': Store.aiModel,
    };
    for (final e in values.entries) {
      final enc = box.encrypt(Uint8List.fromList(utf8.encode(e.value)));
      final r = await http.put(Uri.https('api.github.com', '$_base/${e.key}'),
          headers: _h(),
          body: jsonEncode({'encrypted_value': base64Encode(enc), 'key_id': keyId}));
      if (r.statusCode != 201 && r.statusCode != 204) {
        throw GhException('فشل حفظ ${e.key} (${r.statusCode}).');
      }
    }
    return 'أُرسلت الإعدادات الثلاثة إلى أسرار GitHub ✓';
  }
}
