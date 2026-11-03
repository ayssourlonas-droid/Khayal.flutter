import 'package:flutter/material.dart';

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
