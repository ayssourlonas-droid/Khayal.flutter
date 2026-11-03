/// مفتاح مقارنة الأسماء: أحرف صغيرة، بلا نقاط/شرطات/شرطة سفلية/مسافات، بلا أرقام.
/// إن لم يبقَ شيء (اسم أرقام فقط مثل 2048) نقارن بالأرقام.
/// يجب أن يطابق name_key في tools/import_game/publish.py تماماً.
String nameKey(String name) {
  final base = name.toLowerCase().replaceAll(RegExp(r'[\s._\-]'), '');
  final letters = base.replaceAll(RegExp(r'[0-9]'), '');
  return letters.isEmpty ? base : letters;
}

/// حجمان متقاربان (فرق أقل من 15%). الحجم 0 أو مجهول = غير قابل للمقارنة.
bool similarSize(int a, int b) {
  if (a <= 0 || b <= 0) return false;
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;
  return (hi - lo) / hi <= 0.15;
}
