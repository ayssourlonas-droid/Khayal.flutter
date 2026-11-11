import 'dart:async';
import 'actions_api.dart';

/// طابور الاستيراد على GitHub: يحتفظ GitHub بتشغيل «منتظر» واحد فقط لكل طابور،
/// فإذا أُرسل تشغيل جديد والسابق ما زال منتظراً أُلغي السابق تلقائياً (فتضيع ألعاب).
/// لذلك: (1) نجمع ضغطات «إعادة الاستيراد» ونرسلها معاً في تشغيل واحد، (2) لا نرسل ما دام هناك تشغيل منتظر.
class QueueApi {
  QueueApi._();

  static const _wf = 'import-queue.yml';
  static const _maxPerRun = 30;
  static final Map<String, String> _buf = {}; // رابط المستودع ← اتجاه الشاشة
  static Timer? _timer;
  static bool _flushing = false;
  static bool _warned = false;
  static void Function(String msg, bool error)? _say;

  static int get waiting => _buf.length;

  /// هل يوجد تشغيل طابور لم يبدأ بعد؟ (عند الخطأ نعدّه لا)
  static Future<bool> hasPending() async {
    try {
      final rs = await ActionsApi.runs(_wf, n: 10);
      return rs.any((r) {
        final s = '${r['status']}';
        return s == 'queued' || s == 'pending' || s == 'waiting' || s == 'requested';
      });
    } catch (_) {
      return false;
    }
  }

  /// يضيف لعبة إلى قائمة الإرسال؛ تُرسل القائمة معاً بعد 6 ثوانٍ من آخر إضافة.
  /// أبقِ التطبيق مفتوحاً حتى يظهر إشعار «أُرسلت».
  static void addReimport(String url, String orientation, void Function(String msg, bool error) say) {
    _say = say;
    _buf[url] = (orientation == 'landscape' || orientation == 'both') ? orientation : 'portrait';
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 6), _flush);
    say('أُضيفت إلى قائمة الإرسال (${_buf.length}) — تُرسل معاً بعد ثوانٍ، أضف غيرها إن شئت', false);
  }

  static Future<void> _flush() async {
    if (_flushing || _buf.isEmpty) return;
    _flushing = true;
    try {
      if (await hasPending()) {
        if (!_warned) {
          _warned = true;
          _say?.call('يوجد طابور بانتظار البدء؛ ستُرسل ألعابك تلقائياً حين يتاح (أبقِ التطبيق مفتوحاً)', false);
        }
        _timer = Timer(const Duration(seconds: 30), _flush);
        return;
      }
      _warned = false;
      final take = _buf.entries.take(_maxPerRun).toList();
      await ActionsApi.dispatch(_wf, {
        'urls': take.map((e) => '${e.key} ${e.value}').join('\n'),
        'orientation': 'portrait',
        'prune': 'smart',
        'media': 'safe',
        'ai_test': 'no',
      });
      for (final e in take) {
        _buf.remove(e.key);
      }
      _say?.call('أُرسلت ${take.length} لعبة إلى الطابور ✓ تابع النتائج في تبويب السجل', false);
      if (_buf.isNotEmpty) _timer = Timer(const Duration(seconds: 30), _flush);
    } catch (e) {
      _say?.call('تعذّر الإرسال: $e (القائمة محفوظة؛ أضف لعبة لإعادة المحاولة)', true);
    } finally {
      _flushing = false;
    }
  }
}
