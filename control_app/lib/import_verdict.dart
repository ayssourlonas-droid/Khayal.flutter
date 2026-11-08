import 'dart:convert';
import 'package:flutter/material.dart';
import 'actions_api.dart';
import 'consts.dart';
import 'theme.dart';

/// مستوى الحكم على تشغيل استيراد:
/// أحمر = رفض قاطع، أخضر = نجح ولم تُرصد مشاكل آلية، برتقالي = نجح مع تحذيرات.
enum VLevel { running, red, green, orange, cancelled }

class Verdict {
  final VLevel level;
  final String title; // عنوان قصير بالعربية
  final String why; // تفسير ما حدث
  final String advice; // ما العمل الآن
  final String repo; // رابط المستودع إن عُرف
  final String stage; // المرحلة الجارية (للتشغيل الحالي)
  final List<String> reasons; // أسباب الرفض الخام
  final List<String> warnings; // التحذيرات الخام

  const Verdict({
    required this.level,
    required this.title,
    this.why = '',
    this.advice = '',
    this.repo = '',
    this.stage = '',
    this.reasons = const [],
    this.warnings = const [],
  });

  Color get color {
    switch (level) {
      case VLevel.red:
        return Pal.bad;
      case VLevel.green:
        return Pal.ok;
      case VLevel.orange:
        return Pal.warn;
      case VLevel.running:
        return Pal.purple;
      case VLevel.cancelled:
        return Colors.grey;
    }
  }

  IconData get icon {
    switch (level) {
      case VLevel.red:
        return Icons.block;
      case VLevel.green:
        return Icons.check_circle;
      case VLevel.orange:
        return Icons.warning_amber_rounded;
      case VLevel.running:
        return Icons.autorenew;
      case VLevel.cancelled:
        return Icons.cancel;
    }
  }

  String get label {
    switch (level) {
      case VLevel.red:
        return 'مرفوضة';
      case VLevel.green:
        return 'نجحت';
      case VLevel.orange:
        return 'نجحت مع تحذيرات';
      case VLevel.running:
        return stage.isEmpty ? 'تعمل' : stage;
      case VLevel.cancelled:
        return 'أُلغيت';
    }
  }

  /// اسم قصير للعبة من رابط المستودع (owner/repo).
  String get repoName {
    final m = RegExp(r'github\.com/([^/\s]+/[^/\s#?]+)').firstMatch(repo);
    if (m != null) return m.group(1)!.replaceAll(RegExp(r'\.git$'), '');
    return '';
  }
}

/// نص تفسيري لسبب رفض واحد.
class _Explained {
  final String title;
  final String why;
  final String advice;
  const _Explained(this.title, this.why, this.advice);
}

_Explained explainReason(String t) {
  bool has(String s) => t.contains(s);

  if (has('الرابط ليس رابط مستودع')) {
    return const _Explained('الرابط غير صحيح', 'الرابط ليس مستودع لعبة (قد يكون صفحة مشاكل أو مستخدم أو مجلد).',
        'افتح صفحة المستودع الرئيسية وانسخ رابطها: https://github.com/صاحب/مستودع');
  }
  if (has('المستودع خاص')) {
    return const _Explained('المستودع خاص', 'لا يمكن قراءة مستودع خاص بالاستيراد التلقائي.', 'اختر لعبة في مستودع عام.');
  }
  if (has('لا توجد رخصة')) {
    return const _Explained('لا توجد رخصة', 'بلا رخصة تبقى كل الحقوق لصاحب اللعبة، فلا يصح نشرها.',
        'اطلب من المطوّر إضافة رخصة (مثل MIT)، أو اختر لعبة أخرى.');
  }
  if (has('غير مسموحة للاستيراد')) {
    final m = RegExp(r'الرخصة (\S+)').firstMatch(t);
    return _Explained('رخصة غير مسموحة', 'رخصة ${m?.group(1) ?? 'المستودع'} ليست ضمن الرخص المقبولة للنشر التلقائي.',
        'الرخص المقبولة: ${allowedLicenses.take(9).join('، ')}. ابحث عن لعبة بإحداها.');
  }
  if (has('لعبة جماعية') || has('خادماً لحظياً')) {
    return const _Explained('لعبة جماعية تحتاج خادماً',
        'اللعبة تعتمد على خادم يعمل دائماً (غرف ولاعبون متصلون)، ولا تعمل كموقع ثابت داخل التطبيق.',
        'رفض قاطع وليس خطأ في الاستيراد. ابحث عن لعبة فردية تعمل في المتصفح دون خادم.');
  }
  if (has('خادماً أو قاعدة بيانات')) {
    return const _Explained('تحتاج خادماً أو قاعدة بيانات',
        'المشروع قائم على خادم أو قاعدة بيانات، ولا يمكن استضافته كموقع ثابت.',
        'رفض قاطع وليس خطأ في الاستيراد. اختر لعبة فردية بلا خادم.');
  }
  if (has('موقع/قالب غير مبني')) {
    return const _Explained('ليست لعبة جاهزة', 'هذا موقع أو قالب غير مبني (مثل Jekyll)، وليس لعبة قابلة للتشغيل.',
        'إن كانت لعبة فعلاً فجرّب خانة «مجلد الويب» أو «أمر بناء مخصص» في الخيارات المتقدمة.');
  }
  if (has('لم أجد نسخة ويب')) {
    return const _Explained('لا توجد نسخة ويب', 'لم أجد صفحة index.html ولا أمر بناء في المستودع (قد يكون مشروع Unity أو Godot مصدرياً، أو مجموعة أدوات).',
        'جرّب «مجلد الويب داخل المستودع» أو «أمر بناء مخصص». وإن كان أدوات أو محاكياً فتجاوزه.');
  }
  if (has('فشل البناء')) {
    return const _Explained('فشل بناء المشروع', 'المشروع يحتاج أداة بناء، وفشل أمر البناء. قد يكون السبب إعداداً ناقصاً أو اعتماداً غير متاح.',
        'افتح «فتح في GitHub» وانظر آخر سطور الخطأ في خطوة البناء. وقد تنفع خانة «أمر بناء مخصص». وإن تكرر فتجاوزها.');
  }
  if (has('تجاوز المهلة')) {
    return const _Explained('تجاوز المهلة', 'استغرقت العملية وقتاً أطول من المسموح فأُوقفت.', 'أعد المحاولة مرة. وإن تكرر فاللعبة ثقيلة جداً.');
  }
  if (has('الحجم') && has('كبير جداً')) {
    return const _Explained('حجم كبير جداً', 'حجم اللعبة بعد التنظيف يتجاوز الحد المسموح.', 'اختر لعبة أخف، أو جرّب خيار «تقليل الملفات: ذكي».');
  }
  if (has('عدد الملفات')) {
    return const _Explained('عدد ملفات كبير جداً', 'عدد ملفات اللعبة يتجاوز حد Cloudflare.', 'اختر لعبة أخف.');
  }
  if (has('25MB')) {
    return const _Explained('ملفات كبيرة جداً', 'فيها ملف يتجاوز 25MB، وهو حد Cloudflare للملف الواحد.', 'اختر لعبة أخف.');
  }
  if (has('GitHub 404') || has('Not Found')) {
    return const _Explained('المستودع غير موجود', 'تعذّر الوصول إلى المستودع (غير موجود أو خاص أو الرابط خاطئ).', 'تحقق من الرابط.');
  }
  if (has('rate limit') || has('GitHub 403')) {
    return const _Explained('حدّ طلبات GitHub', 'تجاوز عدد الطلبات المسموح مؤقتاً.', 'انتظر قليلاً ثم أعد المحاولة.');
  }
  return _Explained('سبب آخر', t, 'افتح «فتح في GitHub» لقراءة التفاصيل.');
}

/// نصائح مختصرة لمجموعة التحذيرات.
String adviceForWarnings(List<String> w) {
  final lines = <String>[];
  bool any(String s) => w.any((e) => e.contains(s));
  if (any('تعتمد على خدمات خارجية') || any('ملفات خادم') || any('لا توجد مؤشرات أن هذا الموقع لعبة')) {
    lines.add('جرّبها بزر «تجربة اللعبة» قبل الاعتماد، فقد لا تعمل كاملة.');
  }
  if (any('لا توجد صورة غلاف')) lines.add('استبدل صورة الغلاف قبل الاعتماد.');
  if (any('غير موثّق')) {
    lines.add('أصل الصور/الأصوات غير موثّق؛ ستُنشر وتُعالَج بلاغات أصحاب الحقوق عند ورودها (قرارك السابق).');
  }
  if (any('إعلانات') || any('تتبّع')) lines.add('أُزيلت وسوم إعلانات أو تتبّع من اللعبة؛ تأكد أنها تعمل بعدها.');
  if (any('روابط لمواقع خارجية')) lines.add('فيها روابط لمواقع خارجية؛ راجعها.');
  if (lines.isEmpty) lines.add('راجع التحذيرات ثم جرّب اللعبة قبل الاعتماد.');
  return lines.join('\n');
}

String _stepAr(String name) {
  switch (name) {
    case 'Install headless browser':
      return 'تجهيز المتصفح';
    case 'Fetch, build, sanitize, test':
      return 'جلب اللعبة وبناؤها وفحصها';
    case 'AI plays the game':
      return 'اختبار بالذكاء الاصطناعي';
    case 'Publish and register':
      return 'النشر والتسجيل';
    case 'Set up job':
      return 'تجهيز الخادم';
  }
  return name;
}

List<String> _bullets(String msg) => [
      for (final l in msg.split('\n'))
        if (l.trim().isNotEmpty) l.trim().replaceFirst(RegExp(r'^[•\-]\s*'), ''),
    ];

/// يقرأ نتيجة تشغيل استيراد من GitHub ويحوّلها إلى حكم ملوّن مع تفسير عربي.
class ImportVerdicts {
  ImportVerdicts._();
  static final Map<int, Verdict> _cache = {};

  static Verdict? cached(int runId) => _cache[runId];

  static Future<Verdict> resolve(Map<String, dynamic> run, {bool force = false}) async {
    final id = run['id'] as int;
    final done = '${run['status']}' == 'completed';
    if (done && !force && _cache.containsKey(id)) return _cache[id]!;

    final jobs = await ActionsApi.jobs(id);
    Map<String, dynamic>? job(String n) {
      for (final j in jobs) {
        if ('${j['name']}' == n) return j;
      }
      return null;
    }

    // ── ما زال يعمل: نعرض المرحلة الجارية ──
    if (!done) {
      var stage = '';
      for (final j in jobs) {
        if ('${j['status']}' == 'in_progress') {
          final steps = j['steps'];
          if (steps is List) {
            for (final s in steps) {
              if (s is Map && '${s['status']}' == 'in_progress') stage = _stepAr('${s['name']}');
            }
          }
          if (stage.isEmpty) stage = 'مرحلة ${j['name']}';
        }
      }
      if (stage.isEmpty) stage = '${run['status']}' == 'queued' ? 'في الانتظار' : 'تعمل';
      return Verdict(level: VLevel.running, title: 'جارٍ الاستيراد', stage: stage);
    }

    final cc = '${run['conclusion']}';
    if (cc == 'cancelled') {
      final v = const Verdict(level: VLevel.cancelled, title: 'أُلغي الاستيراد', why: 'أُوقف قبل اكتماله.');
      _cache[id] = v;
      return v;
    }

    final prep = job('prepare');
    final pub = job('publish');

    // ── ملاحظات مرحلة الفحص ──
    var repo = '';
    String status = '';
    var reasons = <String>[];
    var warns = <String>[];
    if (prep != null) {
      try {
        final ann = await ActionsApi.annotations(prep['id'] as int);
        for (final a in ann) {
          final title = a['title'] ?? '';
          final msg = a['message'] ?? '';
          if (title == 'خيال-نتيجة') {
            try {
              final j = jsonDecode(msg);
              if (j is Map) {
                repo = '${j['repo'] ?? ''}';
                status = '${j['status'] ?? ''}';
              }
            } catch (_) {}
          } else if (title == 'أسباب الفشل') {
            reasons = _bullets(msg);
          } else if (title == 'تحذيرات الاستيراد') {
            warns = _bullets(msg);
          } else if (title.contains('تجاوز المهلة') && reasons.isEmpty) {
            reasons = ['تجاوز المهلة: $msg'];
          }
        }
      } catch (_) {}
    }

    Verdict v;
    final prepOk = prep != null && '${prep['conclusion']}' == 'success';
    if (!prepOk) {
      // رفض في مرحلة الفحص
      if (reasons.isNotEmpty) {
        final e = explainReason(reasons.first);
        v = Verdict(
          level: VLevel.red,
          title: e.title,
          why: e.why,
          advice: e.advice,
          repo: repo,
          reasons: reasons,
        );
      } else {
        v = Verdict(
          level: VLevel.red,
          title: 'فشل الاستيراد',
          why: 'فشلت مرحلة الفحص، ولا يوجد سبب مسجَّل (تشغيل قديم قبل إضافة التفسير).',
          advice: 'افتح «فتح في GitHub» لقراءة السبب في السجل، أو أعد الاستيراد بعد رفع آخر نسخة من الأداة.',
          repo: repo,
        );
      }
    } else if (pub != null && '${pub['conclusion']}' == 'failure') {
      var detail = '';
      try {
        final ann = await ActionsApi.annotations(pub['id'] as int);
        for (final a in ann) {
          if ((a['level'] ?? '') == 'failure' && !((a['message'] ?? '').contains('exit code'))) {
            detail = a['message'] ?? '';
            break;
          }
        }
      } catch (_) {}
      v = Verdict(
        level: VLevel.red,
        title: 'نجح الفحص وفشل النشر',
        why: detail.isEmpty ? 'اللعبة سليمة لكن مرحلة النشر فشلت.' : detail,
        advice: 'غالباً إعداد ناقص مثل متغير HOST_BASE_URL، أو تعارض مؤقت. أعد المحاولة، وإن تكرر فافتح السجل.',
        repo: repo,
      );
    } else if (pub != null && '${pub['conclusion']}' != 'success') {
      v = Verdict(
        level: VLevel.red,
        title: 'لم يكتمل النشر',
        why: 'تخطّت مرحلة النشر أو لم تكتمل (قد يكون اختبار الذكاء الاصطناعي فشل).',
        advice: 'افتح «فتح في GitHub» لمعرفة المرحلة التي توقفت.',
        repo: repo,
      );
    } else if (warns.isNotEmpty || status == 'warn') {
      v = Verdict(
        level: VLevel.orange,
        title: 'نجح الاستيراد مع تحذيرات',
        why: 'اللعبة منشورة في «للمراجعة»، لكن الفحص الآلي رصد ${warns.length} ملاحظة تستحق النظر.',
        advice: adviceForWarnings(warns),
        repo: repo,
        warnings: warns,
      );
    } else {
      v = Verdict(
        level: VLevel.green,
        title: 'نجح الاستيراد',
        why: 'اللعبة في «للمراجعة» ولم يرصد الفحص الآلي أي مشكلة.',
        advice: 'جرّبها بزر «تجربة اللعبة» ثم اعتمدها. (الفحص الآلي لا يضمن كل شيء.)',
        repo: repo,
      );
    }
    _cache[id] = v;
    return v;
  }
}
