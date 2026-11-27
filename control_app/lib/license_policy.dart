/// سياسة رخص الأفلام: لكل رخصة ما يجوز تعديله وما يجب الالتزام به.
/// مبنية على نصوص رخص المشاع الإبداعي (Creative Commons) المعروفة، وهي أداة مساعدة وليست استشارة قانونية:
/// راجع صفحة الرخصة عند الشك.

/// عمليات تحرير الفيديو التي يعرفها محرر المتحكم.
enum EditOp { transcode, trim, fade, crop, audioReplace, subtitles, enhance, removeMark }

extension EditOpLabel on EditOp {
  String get label => switch (this) {
        EditOp.transcode => 'تحويل الصيغة/الدقة/FPS',
        EditOp.trim => 'قص وتقطيع',
        EditOp.fade => 'فيد',
        EditOp.crop => 'اقتصاص وتغيير الأبعاد',
        EditOp.audioReplace => 'دبلجة/استبدال الصوت',
        EditOp.subtitles => 'إضافة ترجمة',
        EditOp.enhance => 'تحسين الجودة',
        EditOp.removeMark => 'إزالة علامة مائية',
      };
}

class FilmLicensePolicy {
  final String id; // مطابق لـ allowedFilmLicenses
  final String name;
  final bool publishable; // هل يجوز نشره في خيال (تطبيق بإعلانات)؟
  final Set<EditOp> edits; // ما يجوز تنفيذه عليه
  final bool needsCredit;
  final bool needsChangeNotice; // يجب إعلان أنك عدّلت العمل
  final bool shareAlike; // النسخة المعدلة بنفس الرخصة
  final List<String> notes;
  final String rejectReason;

  const FilmLicensePolicy({
    required this.id,
    required this.name,
    required this.publishable,
    required this.edits,
    this.needsCredit = false,
    this.needsChangeNotice = false,
    this.shareAlike = false,
    this.notes = const [],
    this.rejectReason = '',
  });

  bool allows(EditOp op) => edits.contains(op);

  /// العمليات الممنوعة (لعرضها بالأحمر).
  List<EditOp> get forbidden => [for (final o in EditOp.values) if (!edits.contains(o)) o];

  static const _all = {
    EditOp.transcode,
    EditOp.trim,
    EditOp.fade,
    EditOp.crop,
    EditOp.audioReplace,
    EditOp.subtitles,
    EditOp.enhance,
  };
  static const _free = {..._all, EditOp.removeMark};

  static const _byNotes = [
    'اذكر اسم الصانع ورابط الرخصة بوضوح.',
    'اذكر أنك أجريت تعديلات (قص، دبلجة، ترجمة ...).',
    'لا توحِ بأن صاحب العمل يرعى تطبيقك.',
    'لا تُزل إشعار الحقوق أو الشعار الوارد في العمل.',
  ];

  static const Map<String, FilmLicensePolicy> table = {
    'CC0-1.0': FilmLicensePolicy(
      id: 'CC0-1.0',
      name: 'CC0 — تنازل كامل',
      publishable: true,
      edits: _free,
      notes: ['لا التزامات قانونية. يُستحسن ذكر المصدر.'],
    ),
    'PUBLIC-DOMAIN': FilmLicensePolicy(
      id: 'PUBLIC-DOMAIN',
      name: 'ملك عام',
      publishable: true,
      edits: _free,
      notes: ['لا التزامات قانونية. تأكد أن الحالة «ملك عام» في بلدك أيضاً.', 'يُستحسن ذكر المصدر.'],
    ),
    'CC-BY-4.0': FilmLicensePolicy(
      id: 'CC-BY-4.0',
      name: 'CC BY 4.0 — نسب المصنف',
      publishable: true,
      edits: _all,
      needsCredit: true,
      needsChangeNotice: true,
      notes: _byNotes,
    ),
    'CC-BY-3.0': FilmLicensePolicy(
      id: 'CC-BY-3.0',
      name: 'CC BY 3.0 — نسب المصنف',
      publishable: true,
      edits: _all,
      needsCredit: true,
      needsChangeNotice: true,
      notes: _byNotes,
    ),
    'CC-BY-SA-4.0': FilmLicensePolicy(
      id: 'CC-BY-SA-4.0',
      name: 'CC BY-SA 4.0 — نسب + مشاركة بالمثل',
      publishable: true,
      edits: _all,
      needsCredit: true,
      needsChangeNotice: true,
      shareAlike: true,
      notes: [..._byNotes, 'النسخة المعدلة (بما فيها الدبلجة والترجمة) تُنشر بنفس الرخصة BY-SA.'],
    ),
    'CC-BY-SA-3.0': FilmLicensePolicy(
      id: 'CC-BY-SA-3.0',
      name: 'CC BY-SA 3.0 — نسب + مشاركة بالمثل',
      publishable: true,
      edits: _all,
      needsCredit: true,
      needsChangeNotice: true,
      shareAlike: true,
      notes: [..._byNotes, 'النسخة المعدلة (بما فيها الدبلجة والترجمة) تُنشر بنفس الرخصة BY-SA.'],
    ),
    'OWNED': FilmLicensePolicy(
      id: 'OWNED',
      name: 'ملكي أنا',
      publishable: true,
      edits: _free,
      notes: ['أنت صاحب الحقوق: كل التعديلات جائزة.'],
    ),
    'PARTNER': FilmLicensePolicy(
      id: 'PARTNER',
      name: 'بإذن شريك/صاحب حق',
      publishable: true,
      edits: {EditOp.transcode, EditOp.subtitles},
      needsCredit: true,
      notes: ['التحويل التقني والترجمة فقط افتراضياً.', 'أي تعديل آخر يحتاج إذناً مكتوباً من صاحب الحق (احتفظ به).'],
    ),
  };

  static FilmLicensePolicy? of(String id) => table[id];

  /// سبب رفض رخصة غير مسموحة (NC/ND/نسخة قديمة/غير معروفة).
  static String rejectReasonFor(String family, {String version = ''}) {
    final nc = family.contains('NC');
    final nd = family.contains('ND');
    if (nc) return 'غير تجارية (NC): خيال يعرض إعلانات فهو استعمال تجاري.';
    if (nd) return 'بلا اشتقاق (ND): لا يجوز قص العمل أو دبلجته أو تعديله، وتُرفض في خيال.';
    if (version.isNotEmpty && version != '4.0' && version != '3.0') {
      return 'نسخة قديمة ($version) من الرخصة: افحصها يدوياً ثم اختر الرخصة المقابلة.';
    }
    return 'رخصة غير معروفة.';
  }

  /// سطر الاعتماد الجاهز: «العنوان — الصانع • الرخصة (رابطها) • تم التعديل: ...».
  static String creditText({
    required String title,
    required String creator,
    required String licenseId,
    String licenseUrl = '',
    List<EditOp> changes = const [],
  }) {
    final p = of(licenseId);
    final parts = <String>[
      [if (title.isNotEmpty) '«$title»', if (creator.isNotEmpty) creator].join(' — '),
      if (p != null && licenseId != 'OWNED' && licenseId != 'PARTNER') p.name.split(' — ').first,
      if (licenseUrl.isNotEmpty) licenseUrl,
      if (changes.isNotEmpty && (p?.needsChangeNotice ?? false)) 'تم التعديل: ${changes.map((e) => e.label).join('، ')}',
    ].where((e) => e.trim().isNotEmpty).toList();
    return parts.join(' • ');
  }
}
