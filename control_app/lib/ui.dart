import 'package:flutter/material.dart';
import 'theme.dart';

void toast(BuildContext c, String msg, {bool error = false}) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade800 : null,
      duration: Duration(seconds: error ? 6 : 3),
    ));
}

Future<bool> confirm(BuildContext c, String title, String body, {String ok = 'نعم'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}

Widget field(TextEditingController c, String label,
    {String? hint, int lines = 1, TextInputType? type, bool obscure = false, VoidCallback? onChanged, Widget? suffix}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: c,
      minLines: lines,
      maxLines: obscure ? 1 : lines,
      keyboardType: type,
      obscureText: obscure,
      onChanged: onChanged == null ? null : (_) => onChanged(),
      decoration: InputDecoration(labelText: label, hintText: hint, suffixIcon: suffix),
    ),
  );
}

/// عنوان قسم موحّد في كل شاشات التطبيق: أيقونة ملونة + عنوان + خط رفيع بنفس اللون.
Widget sectionHeader(String title, IconData icon, Color c) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
      child: Row(children: [
        Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: c.withOpacity(0.18), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: c)),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: c)),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: c.withOpacity(0.35), thickness: 1)),
      ]),
    );

/// زر «تشغيل/تجربة/تنفيذ»: أخضر بنص أسود (اللون الدلالي الموحّد للمتابعة).
final ButtonStyle goStyle = FilledButton.styleFrom(backgroundColor: Pal.ok, foregroundColor: Colors.black);

/// زر معلومات/بحث: أزرق.
final ButtonStyle infoStyle = FilledButton.styleFrom(backgroundColor: Pal.info, foregroundColor: Colors.black);
