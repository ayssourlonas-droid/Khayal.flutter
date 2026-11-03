import 'dart:convert';
import 'package:http/http.dart' as http;
import 'github.dart' show GhException;
import 'store.dart';

/// طلب نصي صغير للتأكد أن المفتاح والرابط واسم النموذج صحيحة.
/// إن احتوى الرابط anthropic.com يُستعمل شكل Anthropic، وإلا شكل OpenAI المتوافق.
class AiApi {
  AiApi._();

  static Future<String> test() async {
    final key = Store.aiKey, url = Store.aiEndpoint, model = Store.aiModel;
    if (key.isEmpty || url.isEmpty || model.isEmpty) {
      throw GhException('املأ المفتاح والرابط واسم النموذج أولاً.');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') throw GhException('الرابط يجب أن يبدأ بـ https://');
    final anth = url.contains('anthropic.com');
    final headers = anth
        ? {'x-api-key': key, 'anthropic-version': '2023-06-01', 'content-type': 'application/json'}
        : {'Authorization': 'Bearer $key', 'content-type': 'application/json'};
    final body = anth
        ? {'model': model, 'max_tokens': 20, 'messages': [{'role': 'user', 'content': 'Reply with: OK'}]}
        : {'model': model, 'max_tokens': 20, 'messages': [{'role': 'user', 'content': 'Reply with: OK'}]};
    final r = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 40));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      var m = r.body;
      if (m.length > 300) m = m.substring(0, 300);
      throw GhException('خطأ ${r.statusCode}: ${m.replaceAll(key, '***')}');
    }
    String text = '';
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      text = anth
          ? (j['content'][0]['text'] ?? '').toString()
          : (j['choices'][0]['message']['content'] ?? '').toString();
    } catch (_) {}
    return 'النموذج استجاب ✓ ${text.trim().isEmpty ? '' : '("${text.trim()}")'}\nتنبيه: هذا لا يضمن أنه يدعم الصور؛ اختر نموذجاً مكتوباً أنه Vision.';
  }
}
