import 'package:flutter/material.dart';

/// تصنيف رخص الألعاب لقرار النشر مع إعلانات. هذا ملخص عملي للمراجعة وليس استشارة قانونية.
enum LicClass { free, medium, banned, contract }

class LicInfo {
  final LicClass cls;
  final String name; // الاسم الكامل
  final String summary; // جملة تشرح الرخصة
  final List<String> can; // المسموح
  final List<String> must; // الواجبات (الشروط)
  final List<String> watch; // انتبه
  const LicInfo(this.cls, this.name, this.summary, {this.can = const [], this.must = const [], this.watch = const []});

  static const _comm = 'استخدام تجاري (وإعلانات) وتعديل وتوزيع';
  static const _keep = 'إبقاء نص الرخصة وإشعار حقوق النشر مع الملفات';

  static const Map<String, LicInfo> table = {
    'MIT': LicInfo(LicClass.free, 'MIT', 'متساهلة جداً: كل شيء مسموح بشرط ذكر المؤلف.', can: [_comm], must: [_keep]),
    'Apache-2.0': LicInfo(LicClass.free, 'Apache 2.0', 'متساهلة مع منح براءات اختراع وشرط ذكر التعديلات.',
        can: [_comm, 'ترخيص براءات المساهمين'], must: [_keep, 'ملف NOTICE إن وُجد', 'الإشارة إلى الملفات المعدَّلة']),
    'BSD-2-Clause': LicInfo(LicClass.free, 'BSD 2', 'متساهلة: ذكر المؤلف فقط.', can: [_comm], must: [_keep]),
    'BSD-3-Clause': LicInfo(LicClass.free, 'BSD 3', 'متساهلة، وتمنع استعمال اسم المؤلف في الترويج.',
        can: [_comm], must: [_keep, 'عدم استعمال اسم المؤلف للترويج دون إذن']),
    'ISC': LicInfo(LicClass.free, 'ISC', 'متساهلة (شبيهة بـMIT).', can: [_comm], must: [_keep]),
    'Zlib': LicInfo(LicClass.free, 'zlib', 'متساهلة: لا تنسب العمل لنفسك وأشر إلى التعديل.', can: [_comm], must: ['عدم ادعاء كتابة الأصل', 'الإشارة إلى التعديلات']),
    '0BSD': LicInfo(LicClass.free, '0BSD', 'بلا أي شرط.', can: [_comm]),
    'Unlicense': LicInfo(LicClass.free, 'Unlicense', 'ملكية عامة: بلا شروط.', can: [_comm]),
    'CC0-1.0': LicInfo(LicClass.free, 'CC0', 'تنازل عن الحقوق: بلا شروط.', can: [_comm]),
    'WTFPL': LicInfo(LicClass.free, 'WTFPL', 'بلا شروط تقريباً.', can: [_comm]),
    'BSL-1.0': LicInfo(LicClass.free, 'Boost 1.0', 'متساهلة.', can: [_comm], must: ['إبقاء الإشعار في المصدر']),
    'Artistic-2.0': LicInfo(LicClass.free, 'Artistic 2.0', 'متساهلة مع شروط على النسخ المعدَّلة.', can: [_comm], must: [_keep, 'توضيح أن النسخة معدَّلة']),
    'AFL-3.0': LicInfo(LicClass.free, 'AFL 3.0', 'متساهلة مع ذكر المؤلف.', can: [_comm], must: [_keep]),
    'CC-BY-4.0': LicInfo(LicClass.free, 'CC BY 4.0', 'مسموحة تجارياً بشرط نسب العمل لصاحبه.',
        can: [_comm], must: ['ذكر المؤلف ورابط الرخصة وأي تعديل']),
    'CC-BY-3.0': LicInfo(LicClass.free, 'CC BY 3.0', 'مسموحة تجارياً بشرط نسب العمل لصاحبه.',
        can: [_comm], must: ['ذكر المؤلف ورابط الرخصة وأي تعديل']),
    'GPL-3.0': LicInfo(LicClass.medium, 'GPL 3.0', 'حقوق متبادلة قوية: يجوز الاستخدام التجاري لكن كل ما يُوزَّع منها يبقى GPL بمصدره.',
        can: [_comm],
        must: ['إتاحة المصدر الكامل لأي لاعب (الاستضافة المفتوحة تفي بذلك)', 'إبقاء نص الرخصة', 'أي تعديل تنشره يخضع لـGPL'],
        watch: ['لا تدمجها في كود مغلق', 'لا تحسّن الملفات أو تضغطها بما يحجب المصدر']),
    'GPL-2.0': LicInfo(LicClass.medium, 'GPL 2.0', 'حقوق متبادلة قوية (كـGPL 3 دون بند براءات).',
        can: [_comm], must: ['إتاحة المصدر الكامل', 'إبقاء نص الرخصة'], watch: ['لا تدمجها في كود مغلق']),
    'LGPL-3.0': LicInfo(LicClass.medium, 'LGPL 3.0', 'حقوق متبادلة أخف: التعديلات على المكتبة نفسها يجب نشرها.',
        can: [_comm], must: ['إتاحة مصدر المكتبة وتعديلاتها', 'إبقاء نص الرخصة'], watch: ['راجع إن كان الدمج يمنع المستخدم من استبدال المكتبة']),
    'LGPL-2.1': LicInfo(LicClass.medium, 'LGPL 2.1', 'حقوق متبادلة أخف: التعديلات على المكتبة نفسها يجب نشرها.',
        can: [_comm], must: ['إتاحة مصدر المكتبة وتعديلاتها', 'إبقاء نص الرخصة']),
    'MPL-2.0': LicInfo(LicClass.medium, 'MPL 2.0', 'حقوق متبادلة على مستوى الملف: الملفات المعدَّلة يجب نشرها.',
        can: [_comm], must: ['نشر مصدر الملفات المعدَّلة المرخَّصة بها', 'إبقاء إشعار الرخصة']),
    'CC-BY-SA-4.0': LicInfo(LicClass.medium, 'CC BY-SA 4.0', 'نسب + مشاركة بالمثل: أي مشتق يُنشر بالرخصة نفسها.',
        can: [_comm], must: ['ذكر المؤلف', 'ترخيص أي مشتق بـCC BY-SA'], watch: ['الصور والأصوات المرخَّصة بها تُلزم الأعمال المشتقة منها']),
    'AGPL-3.0': LicInfo(LicClass.banned, 'AGPL 3.0', 'حقوق متبادلة على الشبكة: تُلزم بنشر المصدر لكل من يتعامل مع الخدمة. مرفوضة عمداً في هذا المشروع.',
        watch: ['ممنوعة في الخط الحالي']),
    'CC-BY-NC-4.0': LicInfo(LicClass.banned, 'CC BY-NC 4.0', 'غير تجارية: تمنع الربح والإعلانات.', watch: ['لا تُستعمل مع إعلانات']),
    'CC-BY-NC-SA-4.0': LicInfo(LicClass.banned, 'CC BY-NC-SA 4.0', 'غير تجارية: تمنع الربح والإعلانات.', watch: ['لا تُستعمل مع إعلانات']),
    'CC-BY-ND-4.0': LicInfo(LicClass.banned, 'CC BY-ND 4.0', 'تمنع التعديل (والمعالجة الآلية للملفات تعديل).', watch: ['لا تعدّل ولا تضغط']),
    'OWNED': LicInfo(LicClass.contract, 'ملكية خاصة', 'لعبة تملكها أنت (أو أنشأتها).',
        can: ['كل شيء بلا قيد على الاستخدام'], must: ['إثبات الملكية: مستودعك أو ملفات المشروع'], watch: ['إن شاركك غيرك فيها فوثّق حقوقه']),
    'PARTNER': LicInfo(LicClass.contract, 'اتفاق مع صاحبها', 'لعبة تُنشر بعقد أو اتفاق مكتوب مع صاحبها.',
        can: ['بحسب نص العقد'], must: ['عقد مكتوب (ولو رسائل صريحة) محفوظ خارج المستودع', 'الالتزام بشروطه: المدة، والنطاق، وحصة الأرباح'],
        watch: ['راجع تاريخ الانتهاء', 'هل يشمل الإعلانات والاشتراكات؟', 'هل يشمل الترجمة والتعديل؟']),
  };

  static LicInfo of(String? spdx) {
    final k = (spdx ?? '').trim();
    final t = table[k];
    if (t != null) return t;
    if (k.isEmpty || k == 'NOASSERTION' || k == 'NONE' || k.toLowerCase() == 'null') {
      return const LicInfo(LicClass.banned, 'بلا رخصة', 'لا رخصة = كل الحقوق محفوظة لصاحبها.', watch: ['ممنوع استخدامها بلا إذن مكتوب']);
    }
    if (RegExp(r'(^|-)NC(-|$)', caseSensitive: false).hasMatch(k)) {
      return LicInfo(LicClass.banned, k, 'غير تجارية: تمنع الربح والإعلانات.', watch: const ['لا تُستعمل مع إعلانات']);
    }
    if (RegExp(r'(^|-)ND(-|$)', caseSensitive: false).hasMatch(k)) {
      return LicInfo(LicClass.banned, k, 'تمنع التعديل.', watch: const ['لا تعدّل ولا تضغط']);
    }
    return LicInfo(LicClass.banned, k, 'رخصة غير معروفة في الجدول؛ تُعامل كممنوعة حتى تُراجع يدوياً.', watch: const ['راجع نصها بنفسك أو مع مختص']);
  }

  static String clsLabel(LicClass c) => switch (c) {
        LicClass.free => 'حرة',
        LicClass.medium => 'متوسطة',
        LicClass.banned => 'ممنوعة',
        LicClass.contract => 'بعقد',
      };

  static Color clsColor(LicClass c) => switch (c) {
        LicClass.free => const Color(0xFF3DDC84),
        LicClass.medium => const Color(0xFFFFB74D),
        LicClass.banned => const Color(0xFFFF4D4D),
        LicClass.contract => const Color(0xFF29B6F6),
      };
}
